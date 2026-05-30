import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { UtensilsCrossed, Store, CheckCircle2, ClipboardList } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";

type Order = {
  id: string;
  restaurant_id: string;
  subtotal_gnf: number;
  state: string;
  fulfillment: string;
  created_at: string;
};

export default function RepasAdmin() {
  const [f, setF] = useState<"Tous" | "En cours" | "Livrées">("Tous");
  const [orders, setOrders] = useState<Order[]>([]);
  const [restoCount, setRestoCount] = useState(0);
  const [restoNames, setRestoNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const [o, r] = await Promise.all([
        supabase.from("food_orders").select("id,restaurant_id,subtotal_gnf,state,fulfillment,created_at").order("created_at", { ascending: false }).limit(200),
        supabase.from("food_restaurants").select("id,name").limit(500),
      ]);
      setOrders((o.data ?? []) as Order[]);
      const names: Record<string, string> = {};
      (r.data ?? []).forEach((x: any) => { names[x.id] = x.name; });
      setRestoNames(names);
      setRestoCount(r.data?.length ?? 0);
      setLoading(false);
    })();
  }, []);

  const stats = useMemo(() => ({
    restos: restoCount,
    orders: orders.length,
    inflight: orders.filter((o) => ["placed", "confirmed", "preparing", "ready"].includes(o.state)).length,
    delivered: orders.filter((o) => ["delivered", "picked_up"].includes(o.state)).length,
  }), [orders, restoCount]);

  const filtered = useMemo(() => {
    if (f === "En cours") return orders.filter((o) => ["placed", "confirmed", "preparing", "ready"].includes(o.state));
    if (f === "Livrées") return orders.filter((o) => ["delivered", "picked_up"].includes(o.state));
    return orders;
  }, [orders, f]);

  return (
    <ModulePage module="repas" title="Repas" subtitle="Restaurants et commandes réelles">
      <StatGrid items={[
        { label: "Restaurants", value: loading ? "…" : String(stats.restos), icon: Store },
        { label: "Commandes", value: loading ? "…" : String(stats.orders), icon: ClipboardList },
        { label: "En cours", value: loading ? "…" : String(stats.inflight), icon: UtensilsCrossed },
        { label: "Livrées", value: loading ? "…" : String(stats.delivered), icon: CheckCircle2 },
      ]} />
      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "En cours", "Livrées"] as const).map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["ID", "Restaurant", "Total", "Fulfillment", "Statut", "Créée"]}
        rows={loading ? [] : filtered.map((o) => [
          <span className="font-mono text-xs">{o.id.slice(0, 8)}…</span>,
          restoNames[o.restaurant_id] ?? "—",
          formatGNF(Number(o.subtotal_gnf || 0)),
          o.fulfillment,
          <StatusBadge status={o.state} />,
          new Date(o.created_at).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" }),
        ])}
      />
    </ModulePage>
  );
}
