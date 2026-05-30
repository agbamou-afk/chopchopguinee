import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { ClipboardList, CheckCircle2, X, UtensilsCrossed } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";

type Row = {
  id: string;
  kind: "Course" | "Repas";
  mode: string;
  fare_gnf: number;
  status: string;
  created_at: string;
  driver_id: string | null;
};

export default function OrdersAdmin() {
  const [f, setF] = useState<"Tous" | "Courses" | "Repas">("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const [rides, food] = await Promise.all([
        supabase.from("rides").select("id,mode,fare_gnf,status,created_at,driver_id").order("created_at", { ascending: false }).limit(150),
        supabase.from("food_orders").select("id,subtotal_gnf,state,created_at").order("created_at", { ascending: false }).limit(150),
      ]);
      const list: Row[] = [
        ...((rides.data ?? []) as any[]).map((r) => ({
          id: r.id, kind: "Course" as const, mode: r.mode, fare_gnf: Number(r.fare_gnf || 0),
          status: r.status, created_at: r.created_at, driver_id: r.driver_id,
        })),
        ...((food.data ?? []) as any[]).map((o) => ({
          id: o.id, kind: "Repas" as const, mode: "—", fare_gnf: Number(o.subtotal_gnf || 0),
          status: o.state, created_at: o.created_at, driver_id: null,
        })),
      ].sort((a, b) => +new Date(b.created_at) - +new Date(a.created_at));
      setRows(list);
      setLoading(false);
    })();
  }, []);

  const stats = useMemo(() => ({
    total: rows.length,
    courses: rows.filter((r) => r.kind === "Course").length,
    repas: rows.filter((r) => r.kind === "Repas").length,
    completed: rows.filter((r) => ["completed", "delivered"].includes(r.status)).length,
  }), [rows]);

  const filtered = useMemo(() => {
    if (f === "Courses") return rows.filter((r) => r.kind === "Course");
    if (f === "Repas") return rows.filter((r) => r.kind === "Repas");
    return rows;
  }, [rows, f]);

  return (
    <ModulePage module="orders" title="Courses & Commandes" subtitle="Missions enregistrées (rides + repas)">
      <StatGrid items={[
        { label: "Total (300 récents)", value: loading ? "…" : String(stats.total), icon: ClipboardList },
        { label: "Courses", value: loading ? "…" : String(stats.courses), icon: ClipboardList },
        { label: "Repas", value: loading ? "…" : String(stats.repas), icon: UtensilsCrossed },
        { label: "Terminées", value: loading ? "…" : String(stats.completed), icon: CheckCircle2 },
      ]} />
      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "Courses", "Repas"] as const).map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["ID", "Type", "Mode", "Montant", "Statut", "Créée"]}
        rows={loading ? [] : filtered.map((r) => [
          <span className="font-mono text-xs">{r.id.slice(0, 8)}…</span>,
          r.kind, r.mode, formatGNF(r.fare_gnf),
          <StatusBadge status={r.status} />,
          new Date(r.created_at).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" }),
        ])}
      />
    </ModulePage>
  );
}
