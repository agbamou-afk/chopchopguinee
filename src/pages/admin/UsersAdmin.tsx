import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Users, UserCheck, UserX, ShieldAlert, Trash2, Loader2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

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
  const { isSuperAdmin, role } = useAdminAuth();
  const canHardDelete = isSuperAdmin || role === "god_admin";
  const [filter, setFilter] = useState<"Tous" | "Actifs" | "Suspendus" | "KYC">("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ total: 0, actifs: 0, suspendus: 0, kyc: 0 });
  const [pending, setPending] = useState<Row | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const reload = async () => {
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
  };

  useEffect(() => {
    reload();
  }, []);

  const confirmDelete = async () => {
    if (!pending) return;
    setBusyId(pending.user_id);
    try {
      const { data, error } = await supabase.functions.invoke("admin-delete-user", {
        body: { target_user_id: pending.user_id, confirm: true, reason: "admin_pilot_cleanup" },
      });
      if (error) {
        // supabase-js wraps non-2xx responses in FunctionsHttpError; the JSON
        // body is exposed via error.context (a Response). Try to extract the
        // French message we returned from the edge function.
        let parsed: { error?: string; message?: string; detail?: string; sqlstate?: string } | null = null;
        const ctx = (error as unknown as { context?: Response }).context;
        if (ctx && typeof ctx.json === "function") {
          try { parsed = await ctx.clone().json(); } catch { /* not JSON */ }
        }
        console.error("[admin-delete-user] failed", { error, parsed });
        const base = parsed?.message ?? parsed?.error ?? "Impossible de supprimer ce compte pour le moment.";
        const extra = parsed?.detail ? ` (${parsed.detail}${parsed.sqlstate ? ` · ${parsed.sqlstate}` : ""})` : "";
        toast({
          title: "Suppression impossible",
          description: `${base}${extra}`,
        });
      } else if ((data as { error?: string; message?: string })?.error) {
        const d = data as { error: string; message?: string };
        toast({ title: "Suppression impossible", description: d.message ?? d.error });
      } else {
        const d = (data ?? {}) as { mode?: string; message?: string };
        toast({
          title: d.mode === "hard_deleted" ? "Compte test supprimé" : "Compte anonymisé",
          description: d.message ?? "",
        });
        setPending(null);
        await reload();
      }
    } finally {
      setBusyId(null);
    }
  };

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
        columns={["Nom", "Téléphone", "Statut", "KYC", "Inscrit", "Actions"]}
        rows={loading ? [] : filtered.map((u) => [
          <span className="font-medium">{u.display_name || u.full_name || "—"}</span>,
          <span className="font-mono text-xs">{maskPhone(u.phone)}</span>,
          <StatusBadge status={u.account_status} />,
          `N${u.kyc_level ?? 0}`,
          new Date(u.created_at).toLocaleDateString("fr-FR"),
          canHardDelete ? (
            <Button
              variant="ghost"
              size="sm"
              className="text-destructive hover:text-destructive h-7 px-2"
              disabled={busyId === u.user_id || u.account_status === "deleted"}
              onClick={() => setPending(u)}
            >
              {busyId === u.user_id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5" />}
              <span className="ml-1 text-[11px]">Supprimer compte test</span>
            </Button>
          ) : (
            <span className="text-[11px] text-muted-foreground">—</span>
          ),
        ])}
      />

      <AlertDialog open={!!pending} onOpenChange={(o) => !o && setPending(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Supprimer compte test</AlertDialogTitle>
            <AlertDialogDescription className="space-y-2">
              <span className="block">
                Cette action est destinée aux comptes de test. Si le compte contient des données
                financières/opérationnelles, il sera désactivé/anonymisé au lieu d'être supprimé.
              </span>
              <span className="block font-medium text-foreground">
                {pending?.display_name || pending?.full_name || pending?.user_id}
              </span>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annuler</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={confirmDelete}
            >
              Confirmer
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </ModulePage>
  );
}
