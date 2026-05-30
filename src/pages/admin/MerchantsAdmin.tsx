import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Store, CheckCircle2, Clock, UtensilsCrossed } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

type Row = {
  id: string;
  name: string;
  type: "Restaurant" | "Boutique";
  district: string | null;
  status: string;
  verification_state: string;
  created_at: string;
};

export default function MerchantsAdmin() {
  const [f, setF] = useState<"Tous" | "Restaurants" | "Boutiques" | "Vérifiés">("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const [r, s] = await Promise.all([
        supabase.from("food_restaurants").select("id,name,district,status,verification_state,created_at").order("created_at", { ascending: false }).limit(200),
        supabase.from("merchant_stores").select("id,name,district,status,verification_state,created_at").order("created_at", { ascending: false }).limit(200),
      ]);
      const list: Row[] = [
        ...((r.data ?? []) as any[]).map((x) => ({ ...x, type: "Restaurant" as const })),
        ...((s.data ?? []) as any[]).map((x) => ({ ...x, type: "Boutique" as const })),
      ];
      setRows(list);
      setLoading(false);
    })();
  }, []);

  const stats = useMemo(() => ({
    total: rows.length,
    restaurants: rows.filter((r) => r.type === "Restaurant").length,
    boutiques: rows.filter((r) => r.type === "Boutique").length,
    verified: rows.filter((r) => r.verification_state === "verified").length,
  }), [rows]);

  const filtered = useMemo(() => {
    if (f === "Restaurants") return rows.filter((r) => r.type === "Restaurant");
    if (f === "Boutiques") return rows.filter((r) => r.type === "Boutique");
    if (f === "Vérifiés") return rows.filter((r) => r.verification_state === "verified");
    return rows;
  }, [rows, f]);

  return (
    <ModulePage module="merchants" title="Marchands" subtitle="Restaurants et boutiques enregistrés">
      <StatGrid items={[
        { label: "Marchands", value: loading ? "…" : String(stats.total), icon: Store },
        { label: "Restaurants", value: loading ? "…" : String(stats.restaurants), icon: UtensilsCrossed },
        { label: "Boutiques", value: loading ? "…" : String(stats.boutiques), icon: Store },
        { label: "Vérifiés", value: loading ? "…" : String(stats.verified), icon: CheckCircle2 },
      ]} />
      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "Restaurants", "Boutiques", "Vérifiés"] as const).map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["Marchand", "Type", "Quartier", "Vérification", "Statut", "Inscrit"]}
        rows={loading ? [] : filtered.map((m) => [
          <span className="font-medium">{m.name}</span>,
          m.type,
          m.district ?? "—",
          m.verification_state === "verified"
            ? <span className="inline-flex items-center gap-1 text-emerald-600"><CheckCircle2 className="w-3.5 h-3.5" />Vérifié</span>
            : <span className="inline-flex items-center gap-1 text-muted-foreground"><Clock className="w-3.5 h-3.5" />{m.verification_state}</span>,
          <StatusBadge status={m.status} />,
          new Date(m.created_at).toLocaleDateString("fr-FR"),
        ])}
      />
    </ModulePage>
  );
}
