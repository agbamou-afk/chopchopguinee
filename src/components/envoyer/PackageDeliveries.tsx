import { useCallback, useEffect, useState } from "react";
import { Package, Copy, Share2, Loader2, ShieldCheck, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";
import {
  cancelPackageDelivery,
  getPackageSecrets,
  listMyPackageDeliveries,
  openPackageClaim,
} from "@/lib/packages/api";
import { CancellationConfirmDialog } from "@/components/finance/CancellationConfirmDialog";
import { useEnvoyerClaimsEnabled } from "@/lib/flags/useFeatureFlag";
import {
  PACKAGE_CATEGORY_LABEL,
  PACKAGE_CLAIM_STATE_LABEL,
  PACKAGE_STATUS_LABEL,
  maskPhone,
  type PackageDelivery,
  type PackageSecrets,
} from "@/lib/packages/types";

/**
 * Customer tracking for Envoyer deliveries. Codes are read from the
 * sender-only secrets table (RLS); couriers can never read them.
 * Remains visible even when the Envoyer flag is turned off.
 */
export function PackageDeliveries({ userId }: { userId: string | null }) {
  const [items, setItems] = useState<PackageDelivery[]>([]);
  const [secrets, setSecrets] = useState<Record<string, PackageSecrets | null>>({});
  const [loading, setLoading] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [cancelTarget, setCancelTarget] = useState<PackageDelivery | null>(null);
  const claimsEnabled = useEnvoyerClaimsEnabled();

  const load = useCallback(async () => {
    if (!userId) return;
    setLoading(true);
    try {
      const rows = await listMyPackageDeliveries();
      setItems(rows);
      const pairs = await Promise.all(
        rows
          .filter((r) => r.mission_id)
          .map(async (r) => [r.id, await getPackageSecrets(r.id)] as const),
      );
      setSecrets(Object.fromEntries(pairs));
    } catch {
      /* honest silence — the activity feed still renders */
    } finally {
      setLoading(false);
    }
  }, [userId]);

  useEffect(() => { void load(); }, [load]);

  if (!userId || (!loading && items.length === 0)) return null;

  const share = async (d: PackageDelivery, s: PackageSecrets | null) => {
    const text = [
      `CHOPCHOP Envoyer — ${d.reference}`,
      `Destination : ${d.destination_label ?? "—"}`,
      s?.delivery_code ? `Code de remise (destinataire) : ${s.delivery_code}` : null,
      "Ne communiquez ce code qu’au moment de la remise.",
    ]
      .filter(Boolean)
      .join("\n");
    try {
      if (navigator.share) await navigator.share({ text });
      else {
        await navigator.clipboard.writeText(text);
        toast.success("Détails copiés");
      }
    } catch { /* user dismissed */ }
  };

  const doClaim = async (d: PackageDelivery) => {
    const reason = window.prompt(
      "Décrivez le problème (colis perdu, endommagé, contenu manquant). Minimum 5 caractères :",
    );
    if (!reason || reason.trim().length < 5) return;
    setBusyId(d.id);
    try {
      await openPackageClaim(d.id, reason.trim());
      toast.success("Réclamation ouverte. Le règlement du colis est gelé pendant l’examen.");
      await load();
    } catch (e) {
      const msg = (e as { message?: string })?.message ?? "";
      toast.error(
        msg.includes("CUSTODY_NOT_ESTABLISHED")
          ? "Le coursier n’a pas encore pris le colis en charge."
          : msg.includes("ENVOYER_CLAIMS_DISABLED")
            ? "Les réclamations ne sont pas encore ouvertes."
            : "Réclamation impossible pour le moment.",
      );
    } finally {
      setBusyId(null);
    }
  };

  /**
   * Slice 8: the confirmation amounts come from the canonical server quote
   * rendered by CancellationConfirmDialog. Nothing is computed here.
   */
  const doCancel = async (d: PackageDelivery) => {
    setBusyId(d.id);
    try {
      const res = await cancelPackageDelivery(d.id, "client_cancelled");
      if (res.self_service === false) {
        toast.info("Colis déjà récupéré — un dossier support a été ouvert.");
      } else {
        toast.success(
          `Annulé. Frais ${formatGNF(res.fee_gnf ?? 0)} · remboursement ${formatGNF(res.refund_gnf ?? 0)}`,
        );
      }
      await load();
    } catch {
      toast.error("Annulation impossible pour le moment.");
    } finally {
      setBusyId(null);
      setCancelTarget(null);
    }
  };

  return (
    <section className="mb-4 space-y-3" aria-label="Mes envois de colis">
      <h3 className="px-1 text-[13px] font-semibold text-foreground flex items-center gap-1.5">
        <Package className="w-4 h-4 text-primary" /> Mes envois
      </h3>
      {loading && items.length === 0 && (
        <div className="flex items-center gap-2 px-1 text-muted-foreground text-[12.5px]">
          <Loader2 className="w-3.5 h-3.5 animate-spin" /> Chargement…
        </div>
      )}
      {items.map((d) => {
        const s = secrets[d.id] ?? null;
        const active = !["delivered", "cancelled"].includes(d.package_status);
        const canSelfCancel = active && !s?.pickup_verified_at;
        return (
          <article key={d.id} className="rounded-2xl card-warm p-3.5 space-y-2.5">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="text-[13.5px] font-semibold text-foreground">{d.reference}</p>
                <p className="text-[11.5px] text-muted-foreground">
                  {PACKAGE_CATEGORY_LABEL[d.category] ?? d.category} ·{" "}
                  {PACKAGE_STATUS_LABEL[d.package_status] ?? d.package_status}
                </p>
              </div>
              <span className="text-[13px] font-bold text-foreground shrink-0">
                {formatGNF(d.quoted_amount_gnf)}
              </span>
            </div>

            {d.is_sandbox && (
              <p className="text-[11px] text-muted-foreground">Enregistrement de test (sandbox).</p>
            )}

            <div className="text-[12px] text-muted-foreground space-y-0.5">
              <p>Retrait : {d.pickup_label || "—"}</p>
              <p>Destination : {d.destination_label || "—"}</p>
              <p>
                Destinataire : {d.recipient_name} · {maskPhone(d.recipient_phone)}
              </p>
              <p>Paiement : {d.payment_status}</p>
              {d.refund_request_id && <p>Remboursement demandé (en traitement).</p>}
            </div>

            {s && (
              <div className="rounded-xl border border-border p-2.5 space-y-1.5">
                <p className="text-[11.5px] text-muted-foreground flex items-center gap-1.5">
                  <ShieldCheck className="w-3.5 h-3.5" />
                  Ne donnez chaque code qu’au moment de la remise correspondante.
                </p>
                <div className="flex items-center justify-between">
                  <span className="text-[12.5px] text-foreground">Code de retrait (vous)</span>
                  <button
                    type="button"
                    className="text-[13px] font-bold tracking-widest flex items-center gap-1.5 min-h-[44px]"
                    onClick={() => { void navigator.clipboard.writeText(s.pickup_code); toast.success("Code copié"); }}
                  >
                    {s.pickup_verified_at ? "✓ vérifié" : s.pickup_code}
                    {!s.pickup_verified_at && <Copy className="w-3.5 h-3.5 text-muted-foreground" />}
                  </button>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-[12.5px] text-foreground">Code de remise (destinataire)</span>
                  <span className="text-[13px] font-bold tracking-widest">
                    {s.delivery_verified_at ? "✓ remis" : s.delivery_code}
                  </span>
                </div>
              </div>
            )}

            {d.support_issue_id && (
              <p className="text-[11.5px] text-muted-foreground flex items-center gap-1.5">
                <AlertTriangle className="w-3.5 h-3.5" /> Dossier support ouvert pour ce colis.
              </p>
            )}

            {claimsEnabled && d.claim_state && d.claim_state !== "none" && (
              <p className="text-[11.5px] text-muted-foreground">
                {PACKAGE_CLAIM_STATE_LABEL[d.claim_state] ?? d.claim_state}
              </p>
            )}

            <div className="flex gap-2">
              <Button variant="outline" size="sm" className="flex-1 h-11" onClick={() => share(d, s)}>
                <Share2 className="w-3.5 h-3.5" /> Partager
              </Button>
              {active && (
                <Button
                  variant="ghost"
                  size="sm"
                  className="flex-1 h-11"
                  disabled={busyId === d.id}
                  onClick={() => setCancelTarget(d)}
                >
                  {busyId === d.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : null}
                  {canSelfCancel ? "Annuler" : "Signaler un problème"}
                </Button>
              )}
            </div>

            {claimsEnabled && !!s?.pickup_verified_at &&
              (!d.claim_state || d.claim_state === "none") && (
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full h-11"
                  disabled={busyId === d.id}
                  onClick={() => void doClaim(d)}
                >
                  Ouvrir une réclamation
                </Button>
              )}
          </article>
        );
      })}
    </section>
  );
}