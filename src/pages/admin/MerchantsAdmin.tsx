import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Store, CheckCircle2, Clock, UtensilsCrossed, Hourglass } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";

type Row = {
  id: string;
  name: string;
  type: "Restaurant" | "Boutique";
  district: string | null;
  status: string;
  verification_state: string;
  onboarding_status?: string | null;
  owner_user_id?: string | null;
  phone?: string | null;
  owner_name?: string | null;
  business_type?: string | null;
  stall_number?: string | null;
  rejection_reason?: string | null;
  submitted_at?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  landmark?: string | null;
  address_label?: string | null;
  location_source?: string | null;
  id_photo_path?: string | null;
  selfie_photo_path?: string | null;
  storefront_photo_path?: string | null;
  created_at: string;
};

type Filter =
  | "Tous"
  | "En attente"
  | "Info requise"
  | "Approuvés"
  | "Rejetés"
  | "Restaurants"
  | "Boutiques";

export default function MerchantsAdmin() {
  const [f, setF] = useState<Filter>("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Row | null>(null);
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState("");

  const load = async () => {
    setLoading(true);
    const [r, s] = await Promise.all([
      supabase
        .from("food_restaurants")
        .select("id,name,district,status,verification_state,created_at")
        .order("created_at", { ascending: false })
        .limit(200),
      (supabase as any)
        .from("merchant_stores")
        .select(
          "id,name,district,status,verification_state,created_at,onboarding_status,owner_user_id,phone,owner_name,business_type,stall_number,rejection_reason,submitted_at,latitude,longitude,landmark,address_label,location_source,id_photo_path,selfie_photo_path,storefront_photo_path",
        )
        .order("created_at", { ascending: false })
        .limit(200),
    ]);
    const list: Row[] = [
      ...((r.data ?? []) as any[]).map((x) => ({ ...x, type: "Restaurant" as const })),
      ...((s.data ?? []) as any[]).map((x) => ({ ...x, type: "Boutique" as const })),
    ];
    setRows(list);
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  const stats = useMemo(() => ({
    total: rows.length,
    pending: rows.filter((r) => r.type === "Boutique" && (r.onboarding_status === "submitted" || r.onboarding_status === "in_review")).length,
    needsInfo: rows.filter((r) => r.type === "Boutique" && r.onboarding_status === "needs_info").length,
    approved: rows.filter((r) => r.type === "Boutique" && r.onboarding_status === "approved").length,
  }), [rows]);

  const filtered = useMemo(() => {
    if (f === "Restaurants") return rows.filter((r) => r.type === "Restaurant");
    if (f === "Boutiques") return rows.filter((r) => r.type === "Boutique");
    if (f === "En attente") return rows.filter((r) => r.type === "Boutique" && (r.onboarding_status === "submitted" || r.onboarding_status === "in_review"));
    if (f === "Info requise") return rows.filter((r) => r.type === "Boutique" && r.onboarding_status === "needs_info");
    if (f === "Approuvés") return rows.filter((r) => r.type === "Boutique" && r.onboarding_status === "approved");
    if (f === "Rejetés") return rows.filter((r) => r.type === "Boutique" && r.onboarding_status === "rejected");
    return rows;
  }, [rows, f]);

  const decide = async (decision: "approve" | "reject" | "request_info" | "suspend" | "reactivate") => {
    if (!selected) return;
    setBusy(true);
    const { error } = await (supabase.rpc as any)("admin_merchant_decision", {
      _store_id: selected.id,
      _decision: decision,
      _reason: reason.trim() || null,
    });
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    toast({ title: "Décision enregistrée" });
    setSelected(null);
    setReason("");
    await load();
  };

  return (
    <ModulePage module="merchants" title="Marchands" subtitle="Restaurants, boutiques et demandes d'onboarding">
      <StatGrid items={[
        { label: "Marchands", value: loading ? "…" : String(stats.total), icon: Store },
        { label: "En attente", value: loading ? "…" : String(stats.pending), icon: Hourglass },
        { label: "Info requise", value: loading ? "…" : String(stats.needsInfo), icon: Clock },
        { label: "Approuvés", value: loading ? "…" : String(stats.approved), icon: CheckCircle2 },
      ]} />
      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "En attente", "Info requise", "Approuvés", "Rejetés", "Restaurants", "Boutiques"] as const).map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["Marchand", "Type", "Quartier", "Onboarding", "Statut", "Inscrit", ""]}
        rows={loading ? [] : filtered.map((m) => [
          <span className="font-medium">{m.name}</span>,
          m.type === "Restaurant"
            ? <span className="inline-flex items-center gap-1"><UtensilsCrossed className="w-3.5 h-3.5" />Restaurant</span>
            : <span className="inline-flex items-center gap-1"><Store className="w-3.5 h-3.5" />Boutique</span>,
          m.district ?? "—",
          m.type === "Boutique"
            ? <span className="text-xs">{m.onboarding_status ?? "—"}</span>
            : <span className="text-xs text-muted-foreground">{m.verification_state}</span>,
          <StatusBadge status={m.status} />,
          new Date(m.created_at).toLocaleDateString("fr-FR"),
          m.type === "Boutique" ? (
            <Button size="sm" variant="outline" onClick={() => { setSelected(m); setReason(""); }}>
              Examiner
            </Button>
          ) : <span />,
        ])}
      />

      {selected && (
        <div
          className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-end sm:items-center justify-center p-4"
          onClick={() => setSelected(null)}
        >
          <div
            className="bg-card border border-border rounded-3xl w-full max-w-md p-5 space-y-3 shadow-elevated"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-bold">{selected.name}</h3>
            <dl className="text-xs text-muted-foreground grid grid-cols-2 gap-y-1">
              <dt>Propriétaire</dt><dd className="text-foreground">{selected.owner_name ?? "—"}</dd>
              <dt>Téléphone</dt><dd className="text-foreground">{selected.phone ?? "—"}</dd>
              <dt>Type</dt><dd className="text-foreground">{selected.business_type ?? "—"}</dd>
              <dt>Étal</dt><dd className="text-foreground">{selected.stall_number ?? "—"}</dd>
              <dt>Quartier</dt><dd className="text-foreground">{selected.district ?? "—"}</dd>
              <dt>Onboarding</dt><dd className="text-foreground">{selected.onboarding_status ?? "—"}</dd>
              <dt>Statut</dt><dd className="text-foreground">{selected.status}</dd>
              <dt>Soumis le</dt><dd className="text-foreground">{selected.submitted_at ? new Date(selected.submitted_at).toLocaleDateString("fr-FR") : "—"}</dd>
            </dl>
            {selected.rejection_reason && (
              <p className="text-xs italic text-muted-foreground">« {selected.rejection_reason} »</p>
            )}
            <div>
              <label className="text-xs font-medium">Motif / instructions (optionnel)</label>
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={2}
                className="mt-1 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                placeholder="Ex. Photo de boutique manquante…"
              />
            </div>
            <div className="grid grid-cols-2 gap-2 pt-1">
              <Button onClick={() => decide("approve")} disabled={busy}>Approuver</Button>
              <Button variant="outline" onClick={() => decide("request_info")} disabled={busy}>Demander infos</Button>
              <Button variant="outline" onClick={() => decide("suspend")} disabled={busy}>Suspendre</Button>
              <Button variant="destructive" onClick={() => decide("reject")} disabled={busy}>Rejeter</Button>
            </div>
            <Button variant="ghost" size="sm" className="w-full" onClick={() => setSelected(null)}>Fermer</Button>
          </div>
        </div>
      )}
    </ModulePage>
  );
}