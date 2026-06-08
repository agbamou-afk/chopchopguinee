import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { ShoppingBag, Flag, Eye, TrendingUp } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";

type Row = {
  id: string;
  title: string;
  category: string;
  price_gnf: number | null;
  view_count: number;
  status: string;
  promoted: boolean;
  created_at: string;
  visibility?: string;
  quantity_in_stock?: number | null;
  store_id?: string | null;
  kind?: string;
};

export default function MarcheAdmin() {
  const [f, setF] = useState<"Tous" | "Actives" | "Suspendues" | "Boostées">("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from("marketplace_listings")
        .select("id,title,category,price_gnf,view_count,status,promoted,created_at,visibility,quantity_in_stock,store_id,kind")
        .order("created_at", { ascending: false })
        .limit(200);
      setRows((data ?? []) as Row[]);
      setLoading(false);
    })();
  }, []);

  const stats = useMemo(() => ({
    total: rows.length,
    active: rows.filter((r) => r.status === "active").length,
    suspended: rows.filter((r) => r.status === "suspended").length,
    promoted: rows.filter((r) => r.promoted).length,
    views: rows.reduce((s, r) => s + (r.view_count ?? 0), 0),
  }), [rows]);

  const filtered = useMemo(() => {
    if (f === "Actives") return rows.filter((r) => r.status === "active");
    if (f === "Suspendues") return rows.filter((r) => r.status === "suspended");
    if (f === "Boostées") return rows.filter((r) => r.promoted);
    return rows;
  }, [rows, f]);

  return (
    <ModulePage module="marche" title="Marché" subtitle="Annonces marketplace réelles">
      <StatGrid items={[
        { label: "Annonces", value: loading ? "…" : String(stats.total), icon: ShoppingBag },
        { label: "Actives", value: loading ? "…" : String(stats.active), icon: ShoppingBag },
        { label: "Suspendues", value: loading ? "…" : String(stats.suspended), icon: Flag },
        { label: "Vues cumulées", value: loading ? "…" : String(stats.views), icon: Eye },
      ]} />
      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "Actives", "Suspendues", "Boostées"] as const).map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["ID", "Annonce", "Type", "Catégorie", "Prix", "Stock", "Visibilité", "Statut", "Créée"]}
        rows={loading ? [] : filtered.map((r) => [
          <span className="font-mono text-xs">{r.id.slice(0, 8)}…</span>,
          <span className="font-medium flex items-center gap-1">{r.title}{r.promoted && <TrendingUp className="w-3 h-3 text-primary" />}</span>,
          <span className="text-xs text-muted-foreground">{r.kind ?? "—"}</span>,
          r.category,
          r.price_gnf ? formatGNF(Number(r.price_gnf)) : "—",
          r.quantity_in_stock ?? "—",
          <StatusBadge status={r.visibility ?? "—"} />,
          <StatusBadge status={r.status} />,
          new Date(r.created_at).toLocaleDateString("fr-FR"),
        ])}
      />
    </ModulePage>
  );
}
