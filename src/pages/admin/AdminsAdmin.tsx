import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle, Copy, Loader2, ShieldCheck, UserCog, UserPlus,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter,
} from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { logAction, requestApproval } from "@/lib/admin/approvals";
import { toast } from "@/hooks/use-toast";
import {
  APPROVAL_STATE_LABELS, LifecycleAction, QUORUM_UNAVAILABLE_MESSAGE, QuorumStatus,
  READINESS_LABELS, STAFF_CAPABILITY, STAFF_CLASSES, STAFF_CLASS_LABELS, StaffClass,
  StaffRosterRow, approvalState, availableActions, callStaffLifecycle, fetchLifecycleHistory,
  fetchQuorumStatus, fetchStaffApprovals, fetchStaffRoster, lifecycleMaterial, lifecycleMessage,
  lifecycleTargetType,
} from "@/lib/admin/staffLifecycle";

const ACTION_LABELS: Record<LifecycleAction, string> = {
  CREATE: "Créer",
  DEACTIVATE: "Désactiver",
  REACTIVATE: "Réactiver",
  ROLE_CHANGE: "Changer de classe",
  ACCESS_RESET: "Réinitialiser l’accès",
};

export default function AdminsAdmin() {
  const [tab, setTab] = useState("staff");
  return (
    <ModulePage module="admins" title="Administrateurs" subtitle="Comptes staff, cycle de vie et approbations">
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="staff">Comptes staff</TabsTrigger>
          <TabsTrigger value="lifecycle">Cycle de vie</TabsTrigger>
          <TabsTrigger value="approvals">File d'approbations</TabsTrigger>
        </TabsList>
        <TabsContent value="staff" className="mt-4"><StaffConsole /></TabsContent>
        <TabsContent value="lifecycle" className="mt-4"><LifecycleHistory /></TabsContent>
        <TabsContent value="approvals" className="mt-4"><ApprovalsList /></TabsContent>
      </Tabs>
    </ModulePage>
  );
}

function QuorumBanner({ quorum }: { quorum: QuorumStatus | null }) {
  if (!quorum || !quorum.approval_required) return null;
  if (quorum.quorum_available) {
    return (
      <Card className="p-3 flex items-start gap-2 text-sm border-dashed">
        <ShieldCheck className="w-4 h-4 mt-0.5 text-primary" />
        <span>
          Double validation active : chaque opération doit être approuvée par un autre God Admin
          ({quorum.other_active_god_admins} disponible{quorum.other_active_god_admins > 1 ? "s" : ""}).
        </span>
      </Card>
    );
  }
  return (
    <Card data-testid="quorum-unavailable" className="p-3 flex items-start gap-2 text-sm border-destructive/50">
      <AlertTriangle className="w-4 h-4 mt-0.5 text-destructive" />
      <span>{QUORUM_UNAVAILABLE_MESSAGE}</span>
    </Card>
  );
}

function StaffConsole() {
  const { user } = useAdminAuth();
  const [rows, setRows] = useState<StaffRosterRow[]>([]);
  const [quorum, setQuorum] = useState<QuorumStatus | null>(null);
  const [denied, setDenied] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const [roster, q] = await Promise.all([fetchStaffRoster(), fetchQuorumStatus()]);
    if (roster.error) {
      setDenied(
        /readiness/i.test(roster.error)
          ? "Terminez d’abord le changement de votre mot de passe pour accéder à la gestion du staff."
          : "Accès refusé : la gestion des comptes staff est réservée au God Admin.",
      );
      setRows([]);
    } else {
      setDenied(null);
      setRows(roster.rows);
    }
    setQuorum(q);
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (loading) return <Loader2 className="w-5 h-5 animate-spin" />;
  if (denied) {
    return <Card className="p-8 text-center text-sm text-muted-foreground" data-testid="staff-denied">{denied}</Card>;
  }

  const canAct = quorum ? (!quorum.approval_required || quorum.quorum_available) : false;

  return (
    <div className="space-y-3">
      <QuorumBanner quorum={quorum} />
      <div className="flex flex-wrap gap-2">
        <CreateStaffDialog quorum={quorum} onDone={load} disabled={!canAct} />
      </div>
      {rows.length === 0 && (
        <Card className="p-8 text-center text-sm text-muted-foreground">Aucun compte staff.</Card>
      )}
      {rows.map((r) => (
        <StaffRow key={r.user_id} row={r} callerId={user?.id ?? null} quorum={quorum} onDone={load} canAct={canAct} />
      ))}
    </div>
  );
}

function ReadinessBadge({ row }: { row: StaffRosterRow }) {
  const variant =
    row.readiness === "ready" ? "secondary" : row.readiness === "temp_password_required" ? "default" : "destructive";
  return <Badge variant={variant as any}>{READINESS_LABELS[row.readiness] ?? row.readiness}</Badge>;
}

function StaffRow({
  row, callerId, quorum, onDone, canAct,
}: { row: StaffRosterRow; callerId: string | null; quorum: QuorumStatus | null; onDone: () => void; canAct: boolean }) {
  const actions = useMemo(() => availableActions(row, callerId), [row, callerId]);
  return (
    <Card className="p-4 space-y-3" data-testid="staff-row">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-10 h-10 rounded-xl bg-muted flex items-center justify-center"><UserCog className="w-5 h-5" /></div>
          <div className="min-w-0">
            <p className="font-semibold truncate">{row.full_name ?? row.phone ?? row.user_id.slice(0, 8)}</p>
            <p className="text-xs text-muted-foreground">
              {row.phone ?? "—"}
              {row.last_action ? ` · dernière action : ${row.last_action} (${row.last_outcome ?? "—"})` : ""}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <Badge>{STAFF_CLASS_LABELS[(row.canonical_role ?? "") as StaffClass] ?? row.canonical_role ?? "GOD Admin"}</Badge>
          <Badge variant={row.status === "active" ? "secondary" : "destructive"}>{row.status}</Badge>
          <ReadinessBadge row={row} />
        </div>
      </div>
      {actions.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {actions.map((a) => (
            <LifecycleActionDialog key={a} action={a} row={row} quorum={quorum} onDone={onDone} disabled={!canAct} />
          ))}
        </div>
      )}
    </Card>
  );
}

function newIdempotencyKey(prefix: string) {
  const rand = typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  return `${prefix}-${rand}`;
}

/** Shared approval-aware executor: request approval first, then execute with it. */
async function runLifecycle(params: {
  action: LifecycleAction;
  quorum: QuorumStatus | null;
  targetKey: string;
  role: StaffClass | null;
  body: Record<string, unknown>;
  approvalId: string | null;
  setApprovalId: (v: string) => void;
}) {
  const { action, quorum, targetKey, role, body, approvalId, setApprovalId } = params;
  if (quorum?.approval_required && !quorum.quorum_available) {
    return { ok: false, result: "APPROVER_QUORUM_UNAVAILABLE", message: QUORUM_UNAVAILABLE_MESSAGE };
  }
  let approval = approvalId;
  if (quorum?.approval_required && !approval) {
    try {
      approval = await requestApproval({
        capability: STAFF_CAPABILITY,
        targetType: lifecycleTargetType(action),
        targetId: targetKey,
        material: lifecycleMaterial({ action, role, mustChange: body.must_change_password !== false }),
        module: "admins",
      });
      setApprovalId(approval);
    } catch (e) {
      return { ok: false, result: "PENDING_APPROVAL", message: (e as Error).message };
    }
    return {
      ok: false,
      result: "PENDING_APPROVAL",
      message:
        "Demande de validation créée. Un second God Admin doit l’approuver, puis relancez cette action.",
    };
  }
  return await callStaffLifecycle({ ...body, approval_id: approval });
}

function CreateStaffDialog({
  quorum, onDone, disabled,
}: { quorum: QuorumStatus | null; onDone: () => void; disabled: boolean }) {
  const [open, setOpen] = useState(false);
  const [username, setUsername] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState<StaffClass>("operations_admin");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [idemKey, setIdemKey] = useState(() => newIdempotencyKey("staff-create"));
  const [approvalId, setApprovalId] = useState<string | null>(null);
  const [result, setResult] = useState<null | { email: string; username: string; role: string; temporary_password: string | null }>(null);

  const reset = () => {
    setUsername(""); setDisplayName(""); setEmail(""); setPhone("");
    setRole("operations_admin"); setReason(""); setResult(null);
    setApprovalId(null); setIdemKey(newIdempotencyKey("staff-create"));
  };

  const submit = async () => {
    setBusy(true);
    const res = await runLifecycle({
      action: "CREATE",
      quorum,
      targetKey: email.trim().toLowerCase(),
      role,
      approvalId,
      setApprovalId,
      body: {
        action: "CREATE",
        idempotency_key: idemKey,
        username: username.trim(),
        display_name: displayName.trim() || username.trim(),
        email: email.trim().toLowerCase(),
        phone: phone.trim() || null,
        role,
        must_change_password: true,
        reason: reason.trim(),
      },
    });
    setBusy(false);
    const message = lifecycleMessage(res.result, res.message);
    if (!res.ok) { toast({ title: "Création impossible", description: message }); onDone(); return; }
    setResult({
      email: email.trim().toLowerCase(),
      username: username.trim(),
      role,
      temporary_password: (res as { temporary_password?: string | null }).temporary_password ?? null,
    });
    toast({ title: message });
    onDone();
  };

  const copy = (v: string) => navigator.clipboard?.writeText(v).then(
    () => toast({ title: "Copié" }), () => toast({ title: "Copie impossible" }));

  return (
    <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) reset(); }}>
      <DialogTrigger asChild>
        <Button className="gradient-primary" disabled={disabled}>
          <UserPlus className="w-4 h-4 mr-1" />Créer un compte staff
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader><DialogTitle>Créer un compte staff CHOPCHOP</DialogTitle></DialogHeader>
        {result ? (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Compte créé. Copiez le mot de passe maintenant — il ne sera plus jamais affiché
              et n’est stocké nulle part.
            </p>
            <div className="rounded-lg border p-3 space-y-2 text-sm">
              <Row label="Identifiant" value={result.username} onCopy={copy} />
              <Row label="Email de connexion" value={result.email} onCopy={copy} />
              <Row label="Classe" value={STAFF_CLASS_LABELS[result.role as StaffClass] ?? result.role} />
              {result.temporary_password && (
                <Row label="Mot de passe temporaire" value={result.temporary_password} onCopy={copy} mono />
              )}
            </div>
            <DialogFooter><Button className="w-full" onClick={() => { setOpen(false); reset(); }}>Terminé</Button></DialogFooter>
          </div>
        ) : (
          <>
            <div className="space-y-3">
              <div>
                <Label className="text-xs">Identifiant (username)</Label>
                <Input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="ex. ops.salimatou" />
              </div>
              <div>
                <Label className="text-xs">Nom affiché</Label>
                <Input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="Prénom Nom" />
              </div>
              <div>
                <Label className="text-xs">Email de connexion</Label>
                <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="staff@chopchopguinee.com" />
              </div>
              <div>
                <Label className="text-xs">Téléphone (optionnel)</Label>
                <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+224..." />
              </div>
              <div>
                <Label className="text-xs">Classe</Label>
                <Select value={role} onValueChange={(v) => setRole(v as StaffClass)}>
                  <SelectTrigger aria-label="Classe"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {STAFF_CLASSES.map((c) => (
                      <SelectItem key={c} value={c}>{STAFF_CLASS_LABELS[c]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <p className="text-[11px] text-muted-foreground mt-1">
                  La création de comptes God Admin est impossible depuis cette console.
                </p>
              </div>
              <div>
                <Label className="text-xs">Motif (obligatoire)</Label>
                <Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={2} />
              </div>
              <p className="text-[11px] text-muted-foreground">
                Un mot de passe temporaire est généré par le serveur et affiché une seule fois.
                Le compte devra le changer avant d’accéder à l’administration.
              </p>
            </div>
            <DialogFooter>
              <Button onClick={submit} disabled={busy || !username || !email || !reason.trim()} className="gradient-primary w-full">
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créer le compte"}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function LifecycleActionDialog({
  action, row, quorum, onDone, disabled,
}: { action: LifecycleAction; row: StaffRosterRow; quorum: QuorumStatus | null; onDone: () => void; disabled: boolean }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [role, setRole] = useState<StaffClass>(
    row.canonical_role === "finance_admin" ? "operations_admin" : "finance_admin",
  );
  const [busy, setBusy] = useState(false);
  const [idemKey, setIdemKey] = useState(() => newIdempotencyKey(`staff-${action.toLowerCase()}`));
  const [approvalId, setApprovalId] = useState<string | null>(null);
  const [tempPassword, setTempPassword] = useState<string | null>(null);

  const needsRole = action === "ROLE_CHANGE" || action === "REACTIVATE";

  const submit = async () => {
    setBusy(true);
    const res = await runLifecycle({
      action,
      quorum,
      targetKey: row.user_id,
      role: needsRole ? role : null,
      approvalId,
      setApprovalId,
      body: {
        action,
        idempotency_key: idemKey,
        target_user_id: row.user_id,
        role: needsRole ? role : null,
        must_change_password: true,
        reason: reason.trim(),
      },
    });
    setBusy(false);
    const message = lifecycleMessage(res.result, res.message);
    if (!res.ok) { toast({ title: `${ACTION_LABELS[action]} impossible`, description: message }); onDone(); return; }
    const pw = (res as { temporary_password?: string | null }).temporary_password ?? null;
    if (pw) { setTempPassword(pw); } else { setOpen(false); }
    toast({ title: message });
    onDone();
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(v) => {
        setOpen(v);
        if (!v) { setReason(""); setTempPassword(null); setApprovalId(null); setIdemKey(newIdempotencyKey(`staff-${action.toLowerCase()}`)); }
      }}
    >
      <DialogTrigger asChild>
        <Button size="sm" variant={action === "DEACTIVATE" ? "destructive" : "outline"} disabled={disabled}>
          {ACTION_LABELS[action]}
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader><DialogTitle>{ACTION_LABELS[action]} — {row.full_name ?? row.user_id.slice(0, 8)}</DialogTitle></DialogHeader>
        {tempPassword ? (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Nouveau mot de passe temporaire, affiché une seule fois et stocké nulle part.
            </p>
            <p className="font-mono text-sm rounded-lg border p-3">{tempPassword}</p>
            <DialogFooter><Button className="w-full" onClick={() => setOpen(false)}>Terminé</Button></DialogFooter>
          </div>
        ) : (
          <>
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">
                {action === "DEACTIVATE" && "L’autorité admin est retirée immédiatement. Le compte client reste intact."}
                {action === "REACTIVATE" && "Le compte redevient staff avec une classe explicite et un accès réinitialisé."}
                {action === "ROLE_CHANGE" && "La classe est remplacée ; un changement de mot de passe sera exigé."}
                {action === "ACCESS_RESET" && "Un nouveau mot de passe temporaire est généré et le changement est imposé."}
              </p>
              {needsRole && (
                <div>
                  <Label className="text-xs">Nouvelle classe</Label>
                  <Select value={role} onValueChange={(v) => setRole(v as StaffClass)}>
                    <SelectTrigger aria-label="Nouvelle classe"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {STAFF_CLASSES.map((c) => (
                        <SelectItem key={c} value={c}>{STAFF_CLASS_LABELS[c]}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
              <div>
                <Label className="text-xs">Motif (obligatoire)</Label>
                <Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={2} />
              </div>
            </div>
            <DialogFooter>
              <Button
                onClick={submit}
                disabled={busy || !reason.trim()}
                variant={action === "DEACTIVATE" ? "destructive" : "default"}
                className="w-full"
              >
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : `Confirmer : ${ACTION_LABELS[action]}`}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function LifecycleHistory() {
  const [rows, setRows] = useState<Awaited<ReturnType<typeof fetchLifecycleHistory>>>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { fetchLifecycleHistory().then((r) => { setRows(r); setLoading(false); }); }, []);
  if (loading) return <Loader2 className="w-5 h-5 animate-spin" />;
  if (!rows.length) return <Card className="p-8 text-center text-sm text-muted-foreground">Aucune opération de cycle de vie.</Card>;
  return (
    <div className="space-y-2">
      {rows.map((r) => (
        <Card key={r.id} className="p-3 text-sm flex items-center justify-between gap-3 flex-wrap">
          <div className="min-w-0">
            <p className="font-medium">{r.action} · {r.target_label ?? "—"}</p>
            <p className="text-xs text-muted-foreground">
              {new Date(r.created_at).toLocaleString()}
              {r.reason ? ` · ${r.reason}` : ""}
            </p>
          </div>
          <Badge variant={r.state === "completed" ? "secondary" : r.state === "failed_final" ? "destructive" : "default"}>
            {r.outcome ?? r.error_code ?? r.state}
          </Badge>
        </Card>
      ))}
    </div>
  );
}

function Row({ label, value, onCopy, mono }: { label: string; value: string; onCopy?: (v: string) => void; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <div className="min-w-0">
        <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
        <p className={`truncate ${mono ? "font-mono" : ""}`}>{value}</p>
      </div>
      {onCopy && (
        <Button size="sm" variant="ghost" onClick={() => onCopy(value)}><Copy className="w-3.5 h-3.5" /></Button>
      )}
    </div>
  );
}

function ApprovalsList() {
  const { isSuperAdmin } = useAdminAuth();
  const [rows, setRows] = useState<Awaited<ReturnType<typeof fetchStaffApprovals>>>([]);
  const [others, setOthers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const [staff, { data }] = await Promise.all([
      fetchStaffApprovals(),
      supabase.from("approval_requests").select("*").order("created_at", { ascending: false }).limit(100),
    ]);
    setRows(staff);
    setOthers((data ?? []).filter((r: any) => r.capability !== STAFF_CAPABILITY));
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  // G6: approvals are decided only through the governed server action.
  // Raw table writes are revoked — requester != approver, approver class,
  // intent binding, expiry and single consumption are enforced server-side.
  const review = async (id: string, status: "approved" | "rejected") => {
    const { error } = await (supabase as unknown as {
      rpc: (n: string, a: Record<string, unknown>) => Promise<{ error: { message: string } | null }>;
    }).rpc("admin_review_approval", {
      _approval_id: id,
      _decision: status,
      _note: null,
    });
    if (error) { toast({ title: "Erreur", description: error.message }); return; }
    load();
  };

  if (loading) return <Loader2 className="w-5 h-5 animate-spin" />;
  if (!rows.length && !others.length) {
    return <Card className="p-8 text-center text-sm text-muted-foreground">Aucune demande d'approbation.</Card>;
  }

  return (
    <div className="space-y-3">
      {rows.map((r) => {
        const state = approvalState(r);
        return (
          <Card key={r.id} className="p-4" data-testid="staff-approval">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div className="min-w-0">
                <p className="font-semibold">Cycle de vie staff · {String((r.material as any)?.action ?? "—")}</p>
                <p className="text-xs text-muted-foreground">
                  {r.target_id} · {new Date(r.created_at).toLocaleString()}
                </p>
              </div>
              <Badge variant={state === "ready" ? "default" : state === "pending" ? "secondary" : "destructive"}>
                {APPROVAL_STATE_LABELS[state]}
              </Badge>
            </div>
            <p className="text-[11px] text-muted-foreground mt-2">
              Une demande approuvée n’exécute rien : relancez l’action depuis l’onglet « Comptes staff ».
            </p>
            {isSuperAdmin && state === "pending" && (
              <div className="flex gap-2 mt-3">
                <Button size="sm" onClick={() => review(r.id, "approved")} className="gradient-primary">Approuver</Button>
                <Button size="sm" variant="outline" onClick={() => review(r.id, "rejected")}>Rejeter</Button>
              </div>
            )}
          </Card>
        );
      })}
      {others.map((r) => (
        <Card key={r.id} className="p-4">
          <div className="flex items-center justify-between gap-2">
            <div>
              <p className="font-semibold">{r.action}</p>
              <p className="text-xs text-muted-foreground">{r.module} · {new Date(r.created_at).toLocaleString()}</p>
            </div>
            <Badge variant={r.status === "pending" ? "secondary" : r.status === "approved" ? "default" : "destructive"}>{r.status}</Badge>
          </div>
          {isSuperAdmin && r.status === "pending" && (
            <div className="flex gap-2 mt-3">
              <Button size="sm" onClick={() => review(r.id, "approved")} className="gradient-primary">Approuver</Button>
              <Button size="sm" variant="outline" onClick={() => review(r.id, "rejected")}>Rejeter</Button>
            </div>
          )}
        </Card>
      ))}
    </div>
  );
}
