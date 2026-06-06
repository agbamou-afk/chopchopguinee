import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Users, UserCheck, UserX, ShieldAlert, Trash2, Loader2, Ban, ShieldCheck, MailSearch, Send } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

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
  const canBan = canHardDelete;
  const [filter, setFilter] = useState<"Tous" | "Actifs" | "Suspendus" | "KYC">("Tous");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ total: 0, actifs: 0, suspendus: 0, kyc: 0 });
  const [pending, setPending] = useState<Row | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [banTarget, setBanTarget] = useState<Row | null>(null);
  const [banReason, setBanReason] = useState("");
  const [unbanTarget, setUnbanTarget] = useState<Row | null>(null);
  const [unbanReason, setUnbanReason] = useState("");

  // Email diagnostics
  const [diagEmail, setDiagEmail] = useState("");
  const [diagBusy, setDiagBusy] = useState(false);
  const [diagResult, setDiagResult] = useState<Record<string, unknown> | null>(null);
  const [resendBusy, setResendBusy] = useState(false);

  const runDiagnostics = async () => {
    const email = diagEmail.trim().toLowerCase();
    if (!email || !email.includes("@")) {
      toast({ title: "Email invalide", description: "Saisissez une adresse email valide." });
      return;
    }
    setDiagBusy(true);
    setDiagResult(null);
    const { data, error } = await supabase.rpc("admin_email_delivery_diagnostics", { p_email: email });
    setDiagBusy(false);
    if (error) {
      toast({ title: "Diagnostic impossible", description: error.message });
      return;
    }
    setDiagResult(data as Record<string, unknown>);
  };

  const resendConfirmation = async () => {
    const email = diagEmail.trim().toLowerCase();
    if (!email) return;
    setResendBusy(true);
    const { data, error } = await supabase.functions.invoke("admin-email-resend", {
      body: { email },
    });
    setResendBusy(false);
    if (error) {
      let parsed: { message?: string; error?: string } | null = null;
      const ctx = (error as unknown as { context?: Response }).context;
      if (ctx && typeof ctx.json === "function") {
        try { parsed = await ctx.clone().json(); } catch { /* ignore */ }
      }
      toast({ title: "Renvoi impossible", description: parsed?.message ?? parsed?.error ?? error.message });
      return;
    }
    const d = (data ?? {}) as { message?: string };
    toast({ title: "Renvoi déclenché", description: d.message ?? "Email mis en file d'attente." });
    await runDiagnostics();
  };

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
        const d = (data ?? {}) as { mode?: string; message?: string; email_reusable?: boolean };
        const isDeleted = d.mode === "deleted" || d.mode === "hard_deleted";
        toast({
          title: isDeleted
            ? "Compte test supprimé — email réutilisable"
            : "Compte anonymisé — historique conservé",
          description:
            d.message ??
            (isDeleted
              ? "L'email peut être réutilisé pour un nouveau compte."
              : "L'historique financier/opérationnel est conservé. L'email peut ne pas être réutilisable."),
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

  const confirmBan = async () => {
    if (!banTarget) return;
    if (banReason.trim().length < 3) {
      toast({ title: "Raison requise", description: "Indiquez une raison (3 caractères min)." });
      return;
    }
    setBusyId(banTarget.user_id);
    const { data, error } = await supabase.rpc("admin_ban_user", {
      _target: banTarget.user_id,
      _reason: banReason.trim(),
      _expires_at: null,
    });
    setBusyId(null);
    const res = (data ?? {}) as { ok?: boolean; error?: string };
    if (error || res.ok === false) {
      toast({ title: "Bannissement impossible", description: error?.message ?? res.error ?? "Erreur inconnue." });
      return;
    }
    toast({ title: "Compte banni", description: "L'utilisateur ne peut plus accéder à CHOPCHOP." });
    setBanTarget(null);
    setBanReason("");
    await reload();
  };

  const confirmUnban = async () => {
    if (!unbanTarget) return;
    setBusyId(unbanTarget.user_id);
    const { data, error } = await supabase.rpc("admin_unban_user", {
      _target: unbanTarget.user_id,
      _lift_reason: unbanReason.trim() || "réactivation admin",
    });
    setBusyId(null);
    const res = (data ?? {}) as { ok?: boolean; error?: string };
    if (error || res.ok === false) {
      toast({ title: "Réactivation impossible", description: error?.message ?? res.error ?? "Erreur inconnue." });
      return;
    }
    toast({ title: "Compte réactivé", description: "L'utilisateur peut de nouveau accéder à CHOPCHOP." });
    setUnbanTarget(null);
    setUnbanReason("");
    await reload();
  };

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
            <div className="flex flex-wrap gap-1">
              {u.account_status === "banned" ? (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 px-2 text-emerald-600 hover:text-emerald-600"
                  disabled={busyId === u.user_id}
                  onClick={() => { setUnbanTarget(u); setUnbanReason(""); }}
                >
                  {busyId === u.user_id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <ShieldCheck className="w-3.5 h-3.5" />}
                  <span className="ml-1 text-[11px]">Réactiver</span>
                </Button>
              ) : (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 px-2 text-amber-600 hover:text-amber-600"
                  disabled={busyId === u.user_id || u.account_status === "deleted"}
                  onClick={() => { setBanTarget(u); setBanReason(""); }}
                >
                  <Ban className="w-3.5 h-3.5" />
                  <span className="ml-1 text-[11px]">Bannir</span>
                </Button>
              )}
              <Button
                variant="ghost"
                size="sm"
                className="text-destructive hover:text-destructive h-7 px-2"
                disabled={busyId === u.user_id || u.account_status === "deleted" || u.account_status === "banned"}
                onClick={() => setPending(u)}
              >
                {busyId === u.user_id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5" />}
                <span className="ml-1 text-[11px]">Supprimer compte test</span>
              </Button>
            </div>
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

      {/* Ban dialog */}
      <Dialog open={!!banTarget} onOpenChange={(o) => !o && setBanTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Bannir ce compte</DialogTitle>
            <DialogDescription>
              Cette action bloque l'accès au compte et empêche la réinscription avec les mêmes informations
              (email et téléphone). L'historique financier est conservé.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <p className="text-sm font-medium">
              {banTarget?.display_name || banTarget?.full_name || banTarget?.user_id}
            </p>
            <label className="text-xs text-muted-foreground">Raison du bannissement</label>
            <Textarea
              value={banReason}
              onChange={(e) => setBanReason(e.target.value)}
              placeholder="Ex. fraude, abus, comportement à risque…"
              rows={3}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBanTarget(null)}>Annuler</Button>
            <Button
              className="bg-amber-600 hover:bg-amber-700 text-white"
              onClick={confirmBan}
              disabled={busyId === banTarget?.user_id}
            >
              {busyId === banTarget?.user_id ? <Loader2 className="w-4 h-4 animate-spin" /> : "Confirmer le bannissement"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Unban dialog */}
      <Dialog open={!!unbanTarget} onOpenChange={(o) => !o && setUnbanTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Réactiver le compte</DialogTitle>
            <DialogDescription>
              Lève le bannissement actif. L'utilisateur pourra de nouveau se connecter et l'email/téléphone
              redevient utilisable pour ce compte.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <p className="text-sm font-medium">
              {unbanTarget?.display_name || unbanTarget?.full_name || unbanTarget?.user_id}
            </p>
            <label className="text-xs text-muted-foreground">Raison (optionnel)</label>
            <Textarea
              value={unbanReason}
              onChange={(e) => setUnbanReason(e.target.value)}
              rows={2}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setUnbanTarget(null)}>Annuler</Button>
            <Button onClick={confirmUnban} disabled={busyId === unbanTarget?.user_id} className="gradient-primary">
              {busyId === unbanTarget?.user_id ? <Loader2 className="w-4 h-4 animate-spin" /> : "Réactiver"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </ModulePage>
  );
}
