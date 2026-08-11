import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  Clock,
  Loader2,
  Package,
  ShieldCheck,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";
import { useAuth } from "@/contexts/AuthContext";
import { useEnvoyerEnabled } from "@/lib/flags/useFeatureFlag";
import { LocationField, type PickedLocation } from "./LocationField";
import {
  createPackageCheckout,
  getPackageDelivery,
  listReceivingAccounts,
  requestPackageQuote,
  type ReceivingAccount,
} from "@/lib/packages/api";
import {
  PACKAGE_CATEGORY_HINT,
  PACKAGE_CATEGORY_LABEL,
  PACKAGE_PROHIBITED,
  type PackageCategory,
  type PackageCheckoutResult,
  type PackageQuote,
} from "@/lib/packages/types";
import {
  GUINEA_PHONE_INVALID_MESSAGE,
  extractGuineaLocal,
  isValidGuineaLocal,
  normalizeGuineaPhone,
} from "@/lib/phone/guinea";

interface EnvoyerComposerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Called after a delivery is created so the shell can route to Activité. */
  onCreated?: (result: PackageCheckoutResult) => void;
}

type Step = 1 | 2 | 3 | 4 | 5;

const STEP_TITLES: Record<Step, string> = {
  1: "Itinéraire",
  2: "Destinataire",
  3: "Colis",
  4: "Prix et paiement",
  5: "Confirmation",
};

const CATEGORIES: PackageCategory[] = ["document", "small_parcel", "medium_parcel"];

/** Human error copy for the server error codes Envoyer can return. */
function errorCopy(err: unknown): string {
  const raw = (err as { message?: string })?.message ?? "";
  if (raw.includes("envoyer_disabled")) return "Envoyer n’est pas encore ouvert sur votre compte.";
  if (raw.includes("out_of_service_zone")) return "Cette adresse est hors de notre zone de service.";
  if (raw.includes("unsupported_category")) return "Ce type de colis n’est pas accepté.";
  if (raw.includes("quote_expired")) return "Le prix a expiré. Recalculez le tarif.";
  if (raw.includes("quote_already_used")) return "Ce devis a déjà été utilisé.";
  if (raw.includes("invalid_recipient_phone")) return GUINEA_PHONE_INVALID_MESSAGE;
  if (raw.includes("invalid_recipient_name")) return "Nom du destinataire invalide.";
  if (raw.includes("not_authenticated")) return "Connectez-vous pour envoyer un colis.";
  if (raw.includes("Failed to fetch") || raw.includes("NetworkError"))
    return "Connexion indisponible. Réessayez une fois en ligne.";
  return "Action impossible pour le moment. Réessayez.";
}

/**
 * Envoyer v1 composer — documents and small parcels between people and
 * businesses in Guinea.
 *
 * The client never computes or sends a price: it asks the server for an
 * authoritative quote and then references that quote id at checkout.
 */
export function EnvoyerComposer({ open, onOpenChange, onCreated }: EnvoyerComposerProps) {
  const { user } = useAuth();
  const enabled = useEnvoyerEnabled();

  const [step, setStep] = useState<Step>(1);
  const [pickup, setPickup] = useState<PickedLocation | null>(null);
  const [destination, setDestination] = useState<PickedLocation | null>(null);
  const [recipientName, setRecipientName] = useState("");
  const [recipientLocal, setRecipientLocal] = useState("");
  const [instructions, setInstructions] = useState("");
  const [category, setCategory] = useState<PackageCategory>("document");
  const [description, setDescription] = useState("");
  const [handling, setHandling] = useState("");
  const [acceptedRules, setAcceptedRules] = useState(false);
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  // Slice 6 — declared value, attestation, evidence photos, tender.
  const [declaredValue, setDeclaredValue] = useState("");
  const [attested, setAttested] = useState(false);
  const [photos, setPhotos] = useState<File[]>([]);
  const [tender, setTender] = useState<PackageTender>("cash");
  const [ceiling, setCeiling] = useState<number>(PACKAGE_DECLARED_VALUE_FALLBACK_MAX);

  const [quote, setQuote] = useState<PackageQuote | null>(null);
  const [quoting, setQuoting] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<PackageCheckoutResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [accounts, setAccounts] = useState<ReceivingAccount[]>([]);
  const [liveStatus, setLiveStatus] = useState<{ payment: string; pkg: string } | null>(null);
  const [idempotencyKey] = useState(() =>
    typeof crypto !== "undefined" && "randomUUID" in crypto
      ? crypto.randomUUID()
      : `pkg-${Date.now()}-${Math.random().toString(16).slice(2)}`,
  );

  const declaredEngine = useEnvoyerDeclaredValueEnabled();
  const declaredValueGnf = Number(declaredValue.replace(/\D/g, "")) || 0;

  // The ceiling is policy-owned: never hardcode it in a submitted value.
  useEffect(() => {
    if (!open || !declaredEngine) return;
    let alive = true;
    void getEnvoyerPolicy().then((p) => {
      if (alive && p?.max_declared_value_gnf) setCeiling(Number(p.max_declared_value_gnf));
    });
    return () => { alive = false; };
  }, [open, declaredEngine]);

  // Recoverable errors keep every entered value — we only reset on close.
  useEffect(() => {
    if (open) return;
    const t = window.setTimeout(() => {
      setStep(1);
      setResult(null);
      setError(null);
      setQuote(null);
    }, 250);
    return () => window.clearTimeout(t);
  }, [open]);

  const quoteExpired = useMemo(() => {
    if (!quote) return false;
    return new Date(quote.expires_at).getTime() <= Date.now();
  }, [quote]);

  // Payment hand-off: Orange Money is manual-verification at launch, so the
  // confirmation step must show *where* to pay and then reflect the real
  // server-side state — never claim a payment we have not observed.
  useEffect(() => {
    if (step !== 5 || !result) return;
    let alive = true;
    void listReceivingAccounts().then((a) => { if (alive) setAccounts(a); });
    const poll = async () => {
      const row = await getPackageDelivery(result.package_id);
      if (alive && row) setLiveStatus({ payment: row.payment_status, pkg: row.package_status });
    };
    void poll();
    const id = window.setInterval(poll, 15000);
    return () => { alive = false; window.clearInterval(id); };
  }, [step, result]);

  const fetchQuote = useCallback(async () => {
    if (!pickup || !destination) return;
    setQuoting(true);
    setError(null);
    try {
      const q = await requestPackageQuote({
        pickup: { lat: pickup.lat, lng: pickup.lng, label: pickup.label },
        destination: { lat: destination.lat, lng: destination.lng, label: destination.label },
        category,
      });
      setQuote(q);
    } catch (e) {
      setQuote(null);
      setError(errorCopy(e));
    } finally {
      setQuoting(false);
    }
  }, [pickup, destination, category]);

  const goToPricing = async () => {
    setStep(4);
    await fetchQuote();
  };

  const submit = async () => {
    if (!quote || submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      if (declaredEngine && photos.length > 0) {
        await uploadPackageEvidence(quote.quote_id, photos);
      }
      const res = await createPackageCheckout({
        quoteId: quote.quote_id,
        recipientName: recipientName.trim(),
        recipientPhone: normalizeGuineaPhone(recipientLocal),
        description: description.trim() || null,
        instructions: [instructions.trim(), handling.trim()].filter(Boolean).join(" · ") || null,
        idempotencyKey,
        declaredValueGnf: declaredEngine ? declaredValueGnf : null,
        tender: declaredEngine ? tender : null,
        valueAttested: declaredEngine ? attested : false,
        attestationStatement: declaredEngine ? PACKAGE_ATTESTATION_STATEMENT : null,
      });
      setResult(res);
      setStep(5);
      onCreated?.(res);
    } catch (e) {
      setError(errorCopy(e));
    } finally {
      setSubmitting(false);
    }
  };

  const canStep1 = !!pickup && !!destination;
  const canStep2 = recipientName.trim().length >= 2 && isValidGuineaLocal(extractGuineaLocal(recipientLocal));
  const declaredOk =
    !declaredEngine ||
    (declaredValueGnf > 0 && declaredValueGnf <= ceiling && attested);
  const canStep3 = acceptedRules && declaredOk;
  const canSubmit =
    !!quote &&
    !quoteExpired &&
    acceptedTerms &&
    !submitting &&
    declaredOk &&
    (!declaredEngine || photos.length > 0);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="bottom"
        className="h-[92dvh] p-0 rounded-t-3xl flex flex-col"
        aria-label="Envoyer un colis"
      >
        {/* Header */}
        <div className="shrink-0 px-4 pt-4 pb-3 border-b border-border">
          <div className="flex items-center gap-2">
            {step > 1 && step < 5 ? (
              <button
                type="button"
                onClick={() => setStep((s) => (s - 1) as Step)}
                aria-label="Étape précédente"
                className="h-11 w-11 -ml-2 rounded-xl flex items-center justify-center active:bg-muted"
              >
                <ArrowLeft className="w-5 h-5" />
              </button>
            ) : (
              <div className="h-11 w-11 -ml-2 rounded-xl bg-primary/10 flex items-center justify-center">
                <Package className="w-5 h-5 text-primary" />
              </div>
            )}
            <div className="min-w-0 flex-1">
              <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
                Envoyer · étape {step}/5
              </p>
              <h2 className="text-[17px] font-bold text-foreground leading-tight">
                {STEP_TITLES[step]}
              </h2>
            </div>
            <button
              type="button"
              onClick={() => onOpenChange(false)}
              aria-label="Fermer"
              className="h-11 w-11 -mr-2 rounded-xl flex items-center justify-center active:bg-muted"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          <div className="mt-3 h-1 rounded-full bg-muted overflow-hidden">
            <div
              className="h-full bg-primary transition-all"
              style={{ width: `${(step / 5) * 100}%` }}
            />
          </div>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-4 py-4 space-y-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]">
          {!enabled && (
            <div className="rounded-xl border border-border bg-muted/50 p-3 flex gap-2">
              <AlertTriangle className="w-4 h-4 text-muted-foreground shrink-0 mt-0.5" />
              <p className="text-[12.5px] text-muted-foreground leading-snug">
                Envoyer est encore en préparation. Vous pouvez consulter le formulaire, mais la
                création d’une livraison est refusée par le serveur tant que le service n’est pas
                ouvert.
              </p>
            </div>
          )}

          {!user && (
            <div className="rounded-xl border border-border bg-muted/50 p-3">
              <p className="text-[12.5px] text-muted-foreground leading-snug">
                Connectez-vous pour obtenir un tarif et créer une livraison.
              </p>
            </div>
          )}

          {step === 1 && (
            <>
              <LocationField
                id="pkg-pickup"
                title="Point de retrait"
                placeholder="Où récupérer le colis ?"
                value={pickup}
                onChange={setPickup}
                allowCurrentPosition
              />
              <LocationField
                id="pkg-dest"
                title="Destination"
                placeholder="Où livrer le colis ?"
                value={destination}
                onChange={setDestination}
              />
              <p className="text-[12px] text-muted-foreground">
                Un seul retrait et une seule destination par envoi. Les arrêts multiples ne sont
                pas encore disponibles.
              </p>
            </>
          )}

          {step === 2 && (
            <>
              <div className="space-y-2">
                <label htmlFor="pkg-rname" className="text-[13px] font-semibold text-foreground">
                  Nom du destinataire
                </label>
                <Input
                  id="pkg-rname"
                  value={recipientName}
                  onChange={(e) => setRecipientName(e.target.value.slice(0, 120))}
                  placeholder="Ex. Mariama Diallo"
                  className="h-12"
                />
              </div>
              <div className="space-y-2">
                <label htmlFor="pkg-rphone" className="text-[13px] font-semibold text-foreground">
                  Téléphone du destinataire
                </label>
                <div className="flex items-center gap-2">
                  <span className="h-12 px-3 flex items-center rounded-xl border border-border bg-muted text-[13px] font-medium">
                    +224
                  </span>
                  <Input
                    id="pkg-rphone"
                    value={recipientLocal}
                    onChange={(e) => setRecipientLocal(e.target.value.replace(/\D/g, "").slice(0, 9))}
                    placeholder="6XX XX XX XX"
                    inputMode="numeric"
                    className="h-12 flex-1"
                  />
                </div>
                {recipientLocal.length > 0 && !isValidGuineaLocal(extractGuineaLocal(recipientLocal)) && (
                  <p className="text-[12px] text-destructive">{GUINEA_PHONE_INVALID_MESSAGE}</p>
                )}
              </div>
              <div className="space-y-2">
                <label htmlFor="pkg-instr" className="text-[13px] font-semibold text-foreground">
                  Indications de livraison (repère, étage…)
                </label>
                <Textarea
                  id="pkg-instr"
                  value={instructions}
                  onChange={(e) => setInstructions(e.target.value.slice(0, 500))}
                  placeholder="Ex. Immeuble bleu en face de la pharmacie"
                  className="min-h-[84px]"
                />
              </div>
            </>
          )}

          {step === 3 && (
            <>
              <fieldset className="space-y-2">
                <legend className="text-[13px] font-semibold text-foreground mb-2">
                  Type de colis
                </legend>
                <div className="space-y-2">
                  {CATEGORIES.map((c) => (
                    <button
                      key={c}
                      type="button"
                      onClick={() => { setCategory(c); setQuote(null); }}
                      aria-pressed={category === c}
                      className={`w-full text-left rounded-xl border p-3 min-h-[56px] transition-colors ${
                        category === c
                          ? "border-primary bg-primary/5"
                          : "border-border active:bg-muted"
                      }`}
                    >
                      <p className="text-[13.5px] font-semibold text-foreground">
                        {PACKAGE_CATEGORY_LABEL[c]}
                      </p>
                      <p className="text-[11.5px] text-muted-foreground">{PACKAGE_CATEGORY_HINT[c]}</p>
                    </button>
                  ))}
                </div>
              </fieldset>

              <div className="space-y-2">
                <label htmlFor="pkg-desc" className="text-[13px] font-semibold text-foreground">
                  Contenu du colis
                </label>
                <Textarea
                  id="pkg-desc"
                  value={description}
                  onChange={(e) => setDescription(e.target.value.slice(0, 500))}
                  placeholder="Ex. Dossier administratif, 1 chemise cartonnée"
                  className="min-h-[72px]"
                />
              </div>

              <div className="space-y-2">
                <label htmlFor="pkg-handling" className="text-[13px] font-semibold text-foreground">
                  Précaution particulière (optionnel)
                </label>
                <Input
                  id="pkg-handling"
                  value={handling}
                  onChange={(e) => setHandling(e.target.value.slice(0, 200))}
                  placeholder="Ex. Ne pas plier"
                  className="h-12"
                />
              </div>

              <div className="rounded-xl border border-border p-3 space-y-2">
                <p className="text-[13px] font-semibold text-foreground">Non acceptés</p>
                <ul className="space-y-1">
                  {PACKAGE_PROHIBITED.map((p) => (
                    <li key={p} className="text-[12px] text-muted-foreground leading-snug">• {p}</li>
                  ))}
                </ul>
                <label className="flex items-start gap-2 pt-1 cursor-pointer">
                  <Checkbox
                    checked={acceptedRules}
                    onCheckedChange={(v) => setAcceptedRules(v === true)}
                    className="mt-0.5"
                    aria-label="Je confirme que mon colis est autorisé"
                  />
                  <span className="text-[12.5px] text-foreground leading-snug">
                    Je confirme que mon colis ne contient aucun des éléments interdits ci-dessus.
                  </span>
                </label>
              </div>
            </>
          )}

          {step === 4 && (
            <>
              {quoting ? (
                <div className="flex items-center gap-2 text-muted-foreground py-6">
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span className="text-[13px]">Calcul du tarif…</span>
                </div>
              ) : quote ? (
                <div className="rounded-2xl border border-border p-4 space-y-3">
                  <div className="flex items-baseline justify-between">
                    <span className="text-[13px] text-muted-foreground">Prix de la livraison</span>
                    <span className="text-[22px] font-bold text-foreground">
                      {formatGNF(quote.amount_gnf)}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-[12.5px] text-muted-foreground">
                    <span>Distance estimée</span>
                    <span>{(quote.distance_meters / 1000).toFixed(1)} km</span>
                  </div>
                  <div className="flex items-center justify-between text-[12.5px] text-muted-foreground">
                    <span>Type</span>
                    <span>{PACKAGE_CATEGORY_LABEL[quote.category]}</span>
                  </div>
                  <p className="text-[11.5px] text-muted-foreground flex items-center gap-1.5">
                    <ShieldCheck className="w-3.5 h-3.5" />
                    Tarif calculé par CHOPCHOP (tarif moto). Il ne peut pas être modifié depuis
                    l’application.
                  </p>
                  <p className="text-[11.5px] text-muted-foreground flex items-center gap-1.5">
                    <Clock className="w-3.5 h-3.5" />
                    {quoteExpired
                      ? "Ce tarif a expiré — recalculez avant de payer."
                      : `Valable jusqu’à ${new Date(quote.expires_at).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}`}
                  </p>
                  {quoteExpired && (
                    <Button variant="outline" className="w-full" onClick={fetchQuote}>
                      Recalculer le tarif
                    </Button>
                  )}
                </div>
              ) : (
                <div className="rounded-xl border border-border p-4 space-y-3">
                  <p className="text-[13px] text-muted-foreground">
                    Aucun tarif disponible pour le moment.
                  </p>
                  <Button variant="outline" className="w-full" onClick={fetchQuote}>
                    Réessayer
                  </Button>
                </div>
              )}

              <div className="rounded-xl border border-border p-3 space-y-1.5">
                <p className="text-[13px] font-semibold text-foreground">Paiement</p>
                <p className="text-[12.5px] text-muted-foreground leading-snug">
                  Paiement Orange Money avant l’enlèvement. Aucun solde interne n’est utilisé, et
                  aucun paiement en espèces n’est collecté à la remise.
                </p>
              </div>

              <label className="flex items-start gap-2 cursor-pointer">
                <Checkbox
                  checked={acceptedTerms}
                  onCheckedChange={(v) => setAcceptedTerms(v === true)}
                  className="mt-0.5"
                  aria-label="J’accepte les conditions Envoyer"
                />
                <span className="text-[12.5px] text-foreground leading-snug">
                  J’accepte les conditions Envoyer. CHOPCHOP n’offre pas d’assurance ni de garantie
                  de délai sur cette version.
                </span>
              </label>
            </>
          )}

          {step === 5 && result && (
            <div className="space-y-4">
              <div className="flex items-start gap-3 rounded-2xl border border-border p-4">
                <CheckCircle2 className="w-5 h-5 text-primary mt-0.5" />
                <div className="min-w-0">
                  <p className="text-[14px] font-semibold text-foreground">
                    Livraison enregistrée
                  </p>
                  <p className="text-[12.5px] text-muted-foreground leading-snug mt-1">
                    Référence <strong>{result.reference}</strong>. Le coursier est recherché dès que
                    le paiement Orange Money est confirmé par nos équipes.
                  </p>
                </div>
              </div>

              <div className="rounded-xl border border-border p-3 space-y-2">
                <p className="text-[13px] font-semibold text-foreground">
                  Payer {formatGNF(result.amount_gnf)} par Orange Money
                </p>
                {accounts.length === 0 ? (
                  <p className="text-[12.5px] text-muted-foreground leading-snug">
                    Aucun compte de réception Orange Money n’est publié pour le moment. Contactez le
                    support avant de payer — ne transférez à aucun autre numéro.
                  </p>
                ) : (
                  accounts.map((a) => (
                    <div key={a.id} className="rounded-lg bg-muted/50 p-2.5 space-y-1">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-[12.5px] text-foreground">{a.label}</span>
                        <button
                          type="button"
                          className="text-[13px] font-bold tracking-wide min-h-[44px]"
                          onClick={() => {
                            void navigator.clipboard.writeText(a.phone_e164);
                            toast.success("Numéro copié");
                          }}
                        >
                          {a.phone_e164}
                        </button>
                      </div>
                      {a.public_instructions && (
                        <p className="text-[11.5px] text-muted-foreground leading-snug">
                          {a.public_instructions}
                        </p>
                      )}
                    </div>
                  ))
                )}
                <div className="flex items-center justify-between gap-2 pt-1">
                  <span className="text-[12.5px] text-muted-foreground">Référence à indiquer</span>
                  <button
                    type="button"
                    className="text-[13px] font-bold tracking-widest min-h-[44px]"
                    onClick={() => {
                      void navigator.clipboard.writeText(result.reference);
                      toast.success("Référence copiée");
                    }}
                  >
                    {result.reference}
                  </button>
                </div>
                <p className="text-[11.5px] text-muted-foreground leading-snug">
                  Le paiement est vérifié manuellement par nos équipes. La recherche d’un coursier
                  démarre uniquement après cette vérification — aucun paiement en espèces n’est
                  collecté à la remise.
                </p>
              </div>

              <div className="rounded-xl border border-border p-3">
                <p className="text-[12.5px] text-muted-foreground leading-snug">
                  État du paiement :{" "}
                  <strong>{liveStatus?.payment ?? result.intent_state}</strong>
                  {liveStatus?.pkg ? ` · Livraison : ${liveStatus.pkg}` : ""}. Cet état est lu depuis
                  le serveur. Suivez la livraison et vos codes de remise dans l’onglet{" "}
                  <strong>Activité</strong>.
                </p>
              </div>
              <Button className="w-full h-12" onClick={() => onOpenChange(false)}>
                Voir mon activité
              </Button>
            </div>
          )}

          {error && (
            <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-3 flex gap-2">
              <AlertTriangle className="w-4 h-4 text-destructive shrink-0 mt-0.5" />
              <p className="text-[12.5px] text-destructive leading-snug">{error}</p>
            </div>
          )}
        </div>

        {/* Footer CTA */}
        {step < 5 && (
          <div className="shrink-0 border-t border-border px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] bg-background">
            {step === 1 && (
              <Button className="w-full h-12" disabled={!canStep1} onClick={() => setStep(2)}>
                Continuer
              </Button>
            )}
            {step === 2 && (
              <Button className="w-full h-12" disabled={!canStep2} onClick={() => setStep(3)}>
                Continuer
              </Button>
            )}
            {step === 3 && (
              <Button className="w-full h-12" disabled={!canStep3} onClick={goToPricing}>
                Voir le prix
              </Button>
            )}
            {step === 4 && (
              <Button
                className="w-full h-12"
                disabled={!canSubmit}
                onClick={() => {
                  if (!navigator.onLine) {
                    toast.error("Vous êtes hors ligne. Reconnectez-vous pour créer la livraison.");
                    return;
                  }
                  void submit();
                }}
              >
                {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                {submitting ? "Création…" : "Confirmer et payer"}
              </Button>
            )}
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}