import { ModulePage } from "@/components/admin/ModulePage";
import { DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { Bike, Activity, Star, Wallet, Check, X, AlertTriangle } from "lucide-react";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";

type Tab = "pending" | "approved" | "suspended" | "all";

interface DriverRow {
  user_id: string;
  status: string;
  presence: string;
  vehicle_type: string;
  plate_number: string | null;
  rating: number;
  accept_rate: number;
  cash_debt_gnf: number;
  rejected_reason: string | null;
  suspended_reason: string | null;
  created_at: string;
}

export default function DriversAdmin() {
  const [tab, setTab] = useState<Tab>("pending");
  const [rows, setRows] = useState<DriverRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ approved: 0, online: 0, pending: 0, cashDue: 0 });

  const load = useCallback(async () => {
    setLoading(true);
    let q = supabase.from("driver_profiles").select("*").order("created_at", { ascending: false }).limit(200);
    if (tab === "pending") q = q.eq("status", "pending");
    else if (tab === "approved") q = q.eq("status", "approved");
    else if (tab === "suspended") q = q.in("status", ["suspended", "rejected"]);
    const { data, error } = await q;
    if (error) toast.error(error.message);
    setRows((data as DriverRow[]) || []);

    const { data: agg } = await supabase.from("driver_profiles").select("status,presence,cash_debt_gnf");
    if (agg) {
      setStats({
        approved: agg.filter((r: any) => r.status === "approved").length,
        online: agg.filter((r: any) => r.presence !== "offline").length,
        pending: agg.filter((r: any) => r.status === "pending").length,
        cashDue: agg.reduce((s: number, r: any) => s + (r.cash_debt_gnf || 0), 0),
      });
    }
    setLoading(false);
  }, [tab]);

  useEffect(() => { load(); }, [load]);

  const decide = async (user_id: string, decision: "approve" | "reject") => {
    const reason = decision === "reject" ? (window.prompt("Motif du refus ?") || "") : "";
    const { error } = await supabase.rpc("driver_admin_decide", {
      p_user_id: user_id, p_decision: decision, p_reason: reason || undefined,
    });
    if (error) { toast.error(error.message); return; }
    toast.success(decision === "approve" ? "Chauffeur approuvé" : "Demande refusée");
    load();
  };

  return (
    <ModulePage module="drivers" title="Chauffeurs" subtitle="Onboarding, opérations et commission cash">
      <StatGrid items={[
        { label: "Approuvés", value: String(stats.approved), icon: Bike, tone: "text-emerald-600" },
        { label: "En ligne", value: String(stats.online), icon: Activity, tone: "text-primary" },
        { label: "En attente", value: String(stats.pending), icon: AlertTriangle, tone: "text-amber-500" },
        { label: "Cash dû", value: formatGNF(stats.cashDue), icon: Wallet, tone: "text-rose-600" },
      ]} />

      <div className="flex gap-2 flex-wrap">
        {(["pending", "approved", "suspended", "all"] as Tab[]).map((t) => (
          <FilterChip
            key={t}
            label={t === "pending" ? "En attente" : t === "approved" ? "Approuvés" : t === "suspended" ? "Suspendus / Refusés" : "Tous"}
            active={tab === t}
            onClick={() => setTab(t)}
          />
        ))}
      </div>

      <DataTable
        columns={["Chauffeur", "Véhicule", "Plaque", "Note", "Acceptation", "Cash dû", "Statut", "Actions"]}
        rows={loading ? [] : rows.map((d) => [
          <span className="font-mono text-xs">{d.user_id.slice(0, 8)}…</span>,
          d.vehicle_type,
          d.plate_number || "—",
          <span className="flex items-center gap-1"><Star className="w-3 h-3 text-amber-500 fill-amber-500" />{(d.rating ?? 0).toFixed(1)}</span>,
          `${Math.round((d.accept_rate ?? 0) * 100)}%`,
          formatGNF(d.cash_debt_gnf || 0),
          <StatusBadge status={d.status} />,
          <div className="flex gap-1">
            {d.status === "pending" ? (
              <>
                <Button size="sm" variant="default" className="gradient-primary h-8" onClick={() => decide(d.user_id, "approve")}>
                  <Check className="w-3.5 h-3.5 mr-1" />Approuver
                </Button>
                <Button size="sm" variant="ghost" className="h-8 text-destructive" onClick={() => decide(d.user_id, "reject")}>
                  <X className="w-3.5 h-3.5 mr-1" />Refuser
                </Button>
              </>
            ) : (
              <Button size="sm" variant="ghost" className="h-8">Profil</Button>
            )}
          </div>,
        ])}
      />
    </ModulePage>
  );
}
