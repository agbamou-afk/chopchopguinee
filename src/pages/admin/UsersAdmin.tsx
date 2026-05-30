import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Users, UserCheck, UserX, ShieldAlert } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

type Row = {
  user_id: string;
  display_name: string | null;
  full_name: string | null;
  phone: string | null;
  account_status: string;
  kyc_level: number;
  created_at: string;
};

function maskPhone(p: string | null) {
  if (!p) return "—";
  if (p.length <= 6) return p;
  return p.slice(0, 7) + " ••• ••";
}

export default function UsersAdmin() {
  const [filter, setFilter] = useState<"Tous" | "Actifs" | "Suspendus" | "KYC">("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ total: 0, actifs: 0, suspendus: 0, kyc: 0 });

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from("profiles")
        .select("user_id,display_name,full_name,phone,account_status,kyc_level,created_at")
        .order("created_at", { ascending: false })
        .limit(200);
      const list = (data ?? []) as Row[];
      setRows(list);
      setStats({
        total: list.length,
        actifs: list.filter((r) => r.account_status === "active").length,
        suspendus: list.filter((r) => r.account_status === "suspended").length,
        kyc: list.filter((r) => (r.kyc_level ?? 0) === 0).length,
      });
      setLoading(false);
    })();
  }, []);

  const filtered = useMemo(() => {
    if (filter === "Actifs") return rows.filter((r) => r.account_status === "active");
    if (filter === "Suspendus") return rows.filter((r) => r.account_status === "suspended");
    if (filter === "KYC") return rows.filter((r) => (r.kyc_level ?? 0) === 0);
    return rows;
  }, [rows, filter]);

  return (
    <ModulePage module="users" title="Utilisateurs" subtitle="Profils enregistrés, statuts et KYC">
      <StatGrid items={[
        { label: "Total (200 récents)", value: loading ? "…" : String(stats.total), icon: Users },
        { label: "Actifs", value: loading ? "…" : String(stats.actifs), icon: UserCheck },
        { label: "Suspendus", value: loading ? "…" : String(stats.suspendus), icon: UserX },
        { label: "KYC niveau 0", value: loading ? "…" : String(stats.kyc), icon: ShieldAlert },
      ]} />
      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "Actifs", "Suspendus", "KYC"] as const).map((f) => (
          <FilterChip key={f} label={f === "KYC" ? "KYC à compléter" : f} active={filter === f} onClick={() => setFilter(f)} />
        ))}
      </div>
      <DataTable
        columns={["Nom", "Téléphone", "Statut", "KYC", "Inscrit"]}
        rows={loading ? [] : filtered.map((u) => [
          <span className="font-medium">{u.display_name || u.full_name || "—"}</span>,
          <span className="font-mono text-xs">{maskPhone(u.phone)}</span>,
          <StatusBadge status={u.account_status} />,
          `N${u.kyc_level ?? 0}`,
          new Date(u.created_at).toLocaleDateString("fr-FR"),
        ])}
      />
    </ModulePage>
  );
}
