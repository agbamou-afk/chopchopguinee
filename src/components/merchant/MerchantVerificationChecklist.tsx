import { useMemo, useState } from "react";
import { CheckCircle2, Circle, AlertCircle, Loader2, ChevronDown, ChevronUp } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { MerchantDocUpload } from "./MerchantDocUpload";
import { StoreLocationPicker, type StoreLocation } from "./StoreLocationPicker";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import type { MerchantStore } from "@/hooks/useMerchantIdentity";

type Props = { store: MerchantStore & Record<string, any>; onChanged: () => Promise<void> | void };

type ItemStatus = "todo" | "submitted" | "approved" | "rejected";

function Row({
  label, status, children, open, onToggle,
}: { label: string; status: ItemStatus; children?: React.ReactNode; open: boolean; onToggle: () => void }) {
  const Icon = status === "approved" ? CheckCircle2 : status === "rejected" ? AlertCircle : status === "submitted" ? CheckCircle2 : Circle;
  const tone =
    status === "approved" ? "text-emerald-600" :
    status === "rejected" ? "text-destructive" :
    status === "submitted" ? "text-primary" :
    "text-muted-foreground";
  const badge =
    status === "approved" ? "Validé" :
    status === "rejected" ? "À corriger" :
    status === "submitted" ? "Envoyé" :
    "À compléter";
  return (
    <div className="rounded-xl border border-border/60 bg-card">
      <button onClick={onToggle} className="w-full flex items-center gap-3 p-3 text-left">
        <Icon className={`w-5 h-5 ${tone}`} />
        <span className="flex-1 text-sm font-medium text-foreground">{label}</span>
        <span className={`text-[11px] font-semibold ${tone}`}>{badge}</span>
        {children ? (open ? <ChevronUp className="w-4 h-4 text-muted-foreground" /> : <ChevronDown className="w-4 h-4 text-muted-foreground" />) : null}
      </button>
      {open && children ? <div className="px-3 pb-3 pt-1 border-t border-border/40">{children}</div> : null}
    </div>
  );
}

export function MerchantVerificationChecklist({ store, onChanged }: Props) {
  const [openKey, setOpenKey] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [ownerName, setOwnerName] = useState<string>(store.owner_name ?? "");
  const [whatsapp, setWhatsapp] = useState<string>(store.whatsapp ?? "");
  const [payoutPhone, setPayoutPhone] = useState<string>(store.payout_phone ?? store.phone ?? "");

  const approved = store.onboarding_status === "approved";

  const itemStatus = (filled: boolean, special?: ItemStatus): ItemStatus => {
    if (special) return special;
    if (approved && filled) return "approved";
    if (filled) return "submitted";
    return "todo";
  };

  const toggle = (k: string) => setOpenKey((prev) => (prev === k ? null : k));

  const patchStore = async (patch: Record<string, any>) => {
    setBusy(true);
    const { error } = await (supabase as any).from("merchant_stores").update(patch).eq("id", store.id);
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return false;
    }
    await onChanged();
    return true;
  };

  const onLocation = async (loc: StoreLocation) => {
    const ok = await patchStore({
      latitude: loc.lat,
      longitude: loc.lng,
      district: loc.district ?? store.district ?? null,
      address_label: loc.address_label ?? null,
      landmark: loc.landmark ?? null,
      location_source: loc.location_source,
      location_accuracy_m: loc.location_accuracy_m ?? null,
      location_confirmed_at: new Date().toISOString(),
    });
    if (ok) toast({ title: "Position confirmée" });
  };

  const items = useMemo(() => ([
    {
      key: "owner",
      label: "Identité du responsable",
      status: itemStatus(!!store.owner_name),
      body: (
        <div className="space-y-2">
          <Label className="text-xs">Nom complet du responsable</Label>
          <Input value={ownerName} onChange={(e) => setOwnerName(e.target.value)} placeholder="Nom et prénoms" />
          <Button size="sm" disabled={busy || !ownerName.trim()} onClick={() => patchStore({ owner_name: ownerName.trim() })}>
            Enregistrer
          </Button>
        </div>
      ),
    },
    {
      key: "id",
      label: "Pièce d'identité",
      status: itemStatus(!!store.id_photo_path),
      body: (
        <MerchantDocUpload
          kind="id-card"
          currentPath={store.id_photo_path ?? null}
          onUploaded={(p) => patchStore({ id_photo_path: p })}
        />
      ),
    },
    {
      key: "selfie",
      label: "Selfie de vérification",
      status: itemStatus(!!store.selfie_photo_path),
      body: (
        <MerchantDocUpload
          kind="selfie"
          currentPath={store.selfie_photo_path ?? null}
          onUploaded={(p) => patchStore({ selfie_photo_path: p })}
        />
      ),
    },
    {
      key: "storefront",
      label: "Photo de la boutique",
      status: itemStatus(!!store.storefront_photo_path),
      body: (
        <MerchantDocUpload
          kind="storefront"
          currentPath={store.storefront_photo_path ?? null}
          onUploaded={(p) => patchStore({ storefront_photo_path: p })}
        />
      ),
    },
    {
      key: "location",
      label: "Localisation confirmée",
      status: itemStatus(!!store.location_confirmed_at),
      body: <StoreLocationPicker value={null} onChange={onLocation} />,
    },
    {
      key: "whatsapp",
      label: "Numéro WhatsApp",
      status: itemStatus(!!store.whatsapp),
      body: (
        <div className="space-y-2">
          <Label className="text-xs">WhatsApp</Label>
          <Input value={whatsapp} inputMode="tel" onChange={(e) => setWhatsapp(e.target.value)} placeholder="+224..." />
          <Button size="sm" disabled={busy || !whatsapp.trim()} onClick={() => patchStore({ whatsapp: whatsapp.trim() })}>
            Enregistrer
          </Button>
        </div>
      ),
    },
    {
      key: "payout",
      label: "Numéro de paiement",
      status: itemStatus(!!(store.payout_phone ?? store.phone)),
      body: (
        <div className="space-y-2">
          <Label className="text-xs">Numéro Mobile Money pour recevoir les paiements</Label>
          <Input value={payoutPhone} inputMode="tel" onChange={(e) => setPayoutPhone(e.target.value)} placeholder="+224..." />
          <Button size="sm" disabled={busy || !payoutPhone.trim()} onClick={() => patchStore({ payout_phone: payoutPhone.trim() })}>
            Enregistrer
          </Button>
          <p className="text-[11px] text-muted-foreground">Utilisé pour vos retraits. Visible uniquement par CHOPCHOP.</p>
        </div>
      ),
    },
  ]), [store, ownerName, whatsapp, payoutPhone, busy]);

  const completed = items.filter((i) => i.status !== "todo").length;
  const total = items.length;

  return (
    <div className="bg-card rounded-2xl border border-border/60 p-4 space-y-3">
      <div className="flex items-baseline justify-between gap-2">
        <div>
          <h3 className="font-bold text-foreground">Validation de votre boutique</h3>
          <p className="text-xs text-muted-foreground">
            {approved ? "Boutique validée." : "Préparez votre catalogue maintenant. Vos produits seront visibles après validation."}
          </p>
        </div>
        <span className="text-xs font-semibold text-primary shrink-0">{completed}/{total}</span>
      </div>
      <div className="h-1.5 rounded-full bg-muted overflow-hidden">
        <div className="h-full bg-primary transition-all" style={{ width: `${(completed / total) * 100}%` }} />
      </div>
      <div className="space-y-2">
        {items.map((it) => (
          <Row key={it.key} label={it.label} status={it.status} open={openKey === it.key} onToggle={() => toggle(it.key)}>
            {it.body}
          </Row>
        ))}
      </div>
      {busy && (
        <p className="text-xs text-muted-foreground flex items-center gap-1"><Loader2 className="w-3 h-3 animate-spin" /> Enregistrement…</p>
      )}
    </div>
  );
}