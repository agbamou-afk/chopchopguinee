import { useEffect, useMemo, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge, DataTable, FilterChip } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Users2, Plus, Coins, UserPlus, Gift, AlertCircle } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import {
  listDriverGroups, listMemberships, listCommissions, listReferrals,
  createDriverGroup, assignDriverToGroup, removeDriverFromGroup,
  reviewCommission, markReferral, formatGnf, adminDriverGroupStats,
  listZones, zoneLabel, regenerateGroupReferralCode, payCommissionsBatch,
  type Zone,
  type DriverGroup, type DriverGroupMembership, type DriverGroupCommission, type DriverReferral,
  type DriverGroupStats,
} from "@/lib/admin/driverGroups";

type Tab = "overview" | "groups" | "members" | "commissions" | "referrals" | "analytics";

export default function DriverGroupsAdmin() {
  const [tab, setTab] = useState<Tab>("overview");
  const [groups, setGroups] = useState<DriverGroup[]>([]);
  const [members, setMembers] = useState<DriverGroupMembership[]>([]);
  const [commissions, setCommissions] = useState<DriverGroupCommission[]>([]);
  const [referrals, setReferrals] = useState<DriverReferral[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [loading, setLoading] = useState(true);
  const [createOpen, setCreateOpen] = useState(false);
  const [assignFor, setAssignFor] = useState<DriverGroup | null>(null);

  const reload = async () => {
    setLoading(true);
    try {
      const [g, m, c, r, z] = await Promise.all([
        listDriverGroups(), listMemberships(), listCommissions(), listReferrals(), listZones(),
      ]);
      setGroups(g); setMembers(m); setCommissions(c); setReferrals(r); setZones(z);
    } catch (e: any) {
      toast({ title: "Erreur de chargement", description: e?.message ?? String(e), variant: "destructive" });
    } finally { setLoading(false); }
  };

  useEffect(() => { reload(); }, []);

  const stats = useMemo(() => {
    const activeGroups = groups.filter(g => g.status === "active");
    const leaders = new Set(groups.map(g => g.leader_user_id).filter(Boolean));
    const assignedDrivers = new Set(members.filter(m => m.status === "active").map(m => m.driver_user_id));
    const pendingC = commissions.filter(c => c.status === "pending").reduce((s, c) => s + Number(c.commission_amount_gnf || 0), 0);
    const pendingB = referrals.filter(r => r.status === "bonus_eligible").reduce((s, r) => s + Number(r.bonus_amount_gnf || 0), 0);
    return {
      total: groups.length,
      active: activeGroups.length,
      leaders: leaders.size,
      assigned: assignedDrivers.size,
      pendingCommission: pendingC,
      pendingBonus: pendingB,
    };
  }, [groups, members, commissions, referrals]);

  const groupById = useMemo(() => Object.fromEntries(groups.map(g => [g.id, g])), [groups]);

  return (
    <ModulePage
      module="driver_groups"
      title="Groupes chauffeurs"
      subtitle="Syndicats, leaders et commissions chauffeurs"
      actions={
        <Button size="sm" onClick={() => setCreateOpen(true)} className="h-8">
          <Plus className="w-3.5 h-3.5 mr-1.5" /> Créer un groupe
        </Button>
      }
    >
      <StatGrid items={[
        { label: "Groupes", value: loading ? "…" : String(stats.total), icon: Users2 },
        { label: "Leaders actifs", value: loading ? "…" : String(stats.leaders), icon: UserPlus },
        { label: "Chauffeurs assignés", value: loading ? "…" : String(stats.assigned), icon: Users2 },
        { label: "Commissions en attente", value: loading ? "…" : formatGnf(stats.pendingCommission), icon: Coins },
      ]} />

      <div className="flex flex-wrap gap-2">
        {([
          ["overview", "Vue d'ensemble"],
          ["groups", `Groupes (${groups.length})`],
          ["members", `Membres (${members.filter(m => m.status === "active").length})`],
          ["commissions", `Commissions (${commissions.length})`],
          ["referrals", `Parrainages (${referrals.length})`],
          ["analytics", "Analytics"],
        ] as [Tab, string][]).map(([k, l]) => (
          <FilterChip key={k} label={l} active={tab === k} onClick={() => setTab(k)} />
        ))}
      </div>

      {loading ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Chargement…</Card>
      ) : tab === "overview" ? (
        <OverviewPanel groups={groups} members={members} commissions={commissions} referrals={referrals} />
      ) : tab === "groups" ? (
        <GroupsTable groups={groups} members={members} onAssign={(g) => setAssignFor(g)} onChanged={reload} />
      ) : tab === "members" ? (
        <MembersTable members={members} groupById={groupById} onChanged={reload} />
      ) : tab === "commissions" ? (
        <CommissionsTable rows={commissions} groupById={groupById} onChanged={reload} />
      ) : tab === "referrals" ? (
        <ReferralsTable rows={referrals} groupById={groupById} onChanged={reload} />
      ) : (
        <AnalyticsPanel groupById={groupById} />
      )}

      <CreateGroupSheet open={createOpen} onOpenChange={setCreateOpen} onCreated={reload} zones={zones} />
      <AssignDriverDialog group={assignFor} onClose={() => setAssignFor(null)} onAssigned={reload} zones={zones} />
    </ModulePage>
  );
}

function OverviewPanel({ groups, members, commissions, referrals }: {
  groups: DriverGroup[]; members: DriverGroupMembership[];
  commissions: DriverGroupCommission[]; referrals: DriverReferral[];
}) {
  if (groups.length === 0) {
    return (
      <Card className="p-8 text-center text-sm text-muted-foreground border-dashed">
        Aucun groupe chauffeur configuré.
      </Card>
    );
  }
  return (
    <div className="grid md:grid-cols-2 gap-3">
      {groups.map((g) => {
        const activeMembers = members.filter(m => m.group_id === g.id && m.status === "active").length;
        const pending = commissions.filter(c => c.group_id === g.id && c.status === "pending").reduce((s, c) => s + Number(c.commission_amount_gnf), 0);
        const bonus = referrals.filter(r => r.group_id === g.id && r.status === "bonus_eligible").reduce((s, r) => s + Number(r.bonus_amount_gnf), 0);
        return (
          <Card key={g.id} className="p-4 space-y-2">
            <div className="flex items-center justify-between gap-2">
              <div className="min-w-0">
                <p className="font-semibold text-sm truncate">{g.name}</p>
                <p className="text-xs text-muted-foreground truncate">
                  {g.leader_name || "—"} {g.leader_phone ? `· ${g.leader_phone}` : ""}
                </p>
              </div>
              <StatusBadge status={g.status} />
            </div>
            <div className="grid grid-cols-3 gap-2 text-[11px]">
              <div><span className="text-muted-foreground">Commission</span><p className="tabular-nums">{Number(g.commission_percent).toFixed(2)}%</p></div>
              <div><span className="text-muted-foreground">Chauffeurs</span><p className="tabular-nums">{activeMembers}</p></div>
              <div><span className="text-muted-foreground">Bonus signup</span><p className="tabular-nums">{formatGnf(g.signup_bonus_gnf)}</p></div>
            </div>
            <div className="grid grid-cols-2 gap-2 text-[11px] pt-1 border-t border-border/50">
              <div><span className="text-muted-foreground">Commission en attente</span><p className="tabular-nums">{formatGnf(pending)}</p></div>
              <div><span className="text-muted-foreground">Bonus à payer</span><p className="tabular-nums">{formatGnf(bonus)}</p></div>
            </div>
            {g.assigned_zones?.length > 0 && (
              <div className="flex flex-wrap gap-1 pt-1">
                {g.assigned_zones.map(z => <span key={z} className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{z}</span>)}
              </div>
            )}
          </Card>
        );
      })}
    </div>
  );
}

function GroupsTable({ groups, members, onAssign, onChanged }: {
  groups: DriverGroup[]; members: DriverGroupMembership[];
  onAssign: (g: DriverGroup) => void; onChanged: () => void;
}) {
  if (groups.length === 0) {
    return <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucun groupe chauffeur configuré.</Card>;
  }
  return (
    <DataTable
      columns={["Nom", "Leader", "Statut", "Commission", "Bonus", "Chauffeurs", "Zones", "Actions"]}
      rows={groups.map(g => [
        <span className="font-medium">{g.name}</span>,
        <span className="text-xs">{g.leader_name || "—"}<br /><span className="text-muted-foreground">{g.leader_phone || ""}</span></span>,
        <StatusBadge status={g.status} />,
        `${Number(g.commission_percent).toFixed(2)}%`,
        formatGnf(g.signup_bonus_gnf),
        String(members.filter(m => m.group_id === g.id && m.status === "active").length),
        <span className="text-xs">{g.assigned_zones?.join(", ") || "—"}</span>,
        <Button size="sm" variant="outline" className="h-7 text-[11px]" onClick={() => onAssign(g)}>
          <UserPlus className="w-3 h-3 mr-1" /> Assigner
        </Button>,
      ])}
    />
  );
}

function MembersTable({ members, groupById, onChanged }: {
  members: DriverGroupMembership[]; groupById: Record<string, DriverGroup>; onChanged: () => void;
}) {
  const active = members.filter(m => m.status === "active");
  if (active.length === 0) {
    return <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucun chauffeur assigné.</Card>;
  }
  const remove = async (id: string) => {
    const reason = window.prompt("Raison du retrait ?") ?? null;
    try { await removeDriverFromGroup(id, reason); toast({ title: "Chauffeur retiré" }); onChanged(); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };
  return (
    <DataTable
      columns={["Chauffeur", "Groupe", "Zone", "Assigné le", "Actions"]}
      rows={active.map(m => [
        <span className="font-mono text-[11px]">{m.driver_user_id.slice(0, 8)}…</span>,
        groupById[m.group_id]?.name ?? "—",
        m.assigned_zone || "—",
        new Date(m.joined_at).toLocaleDateString("fr-FR"),
        <Button size="sm" variant="ghost" className="h-7 text-[11px] text-destructive" onClick={() => remove(m.id)}>Retirer</Button>,
      ])}
    />
  );
}

function CommissionsTable({ rows, groupById, onChanged }: {
  rows: DriverGroupCommission[]; groupById: Record<string, DriverGroup>; onChanged: () => void;
}) {
  if (rows.length === 0) {
    return <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucune commission enregistrée.</Card>;
  }
  const act = async (id: string, action: "approve" | "mark_paid" | "reverse") => {
    try {
      let reason: string | null = null;
      if (action === "reverse") reason = window.prompt("Raison de l'annulation ?") ?? null;
      await reviewCommission(id, action, reason);
      toast({ title: action === "mark_paid" ? "Commission payée via ChopWallet" : "Commission mise à jour" });
      onChanged();
    }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };
  return (
    <>
      <Card className="p-3 bg-muted/30 border-dashed text-[11px] text-muted-foreground flex items-start gap-2">
        <AlertCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
        <span>« Payer (ChopWallet) » crédite le portefeuille du leader via RPC sécurisée. L'annulation après paiement débite automatiquement le leader.</span>
      </Card>
      <DataTable
        columns={["Date", "Groupe", "Chauffeur", "Source", "Gain chauffeur", "%", "Commission", "Statut", "Wallet TX", "Actions"]}
        rows={rows.map(c => [
          new Date(c.created_at).toLocaleDateString("fr-FR"),
          groupById[c.group_id]?.name ?? "—",
          <span className="font-mono text-[11px]">{c.driver_user_id.slice(0, 8)}…</span>,
          c.source_type,
          formatGnf(c.gross_driver_earning_gnf),
          `${Number(c.commission_percent).toFixed(2)}%`,
          formatGnf(c.commission_amount_gnf),
          <StatusBadge status={c.status} />,
          <span className="font-mono text-[10px] text-muted-foreground">{(c as any).wallet_transaction_id ? String((c as any).wallet_transaction_id).slice(0, 8) + "…" : "—"}</span>,
          <div className="flex gap-1">
            {c.status === "pending" && <Button size="sm" variant="outline" className="h-6 text-[10px]" onClick={() => act(c.id, "approve")}>Approuver</Button>}
            {c.status === "approved" && <Button size="sm" variant="outline" className="h-6 text-[10px]" onClick={() => act(c.id, "mark_paid")}>Payer (ChopWallet)</Button>}
            {(c.status === "pending" || c.status === "approved" || c.status === "paid") && <Button size="sm" variant="ghost" className="h-6 text-[10px] text-destructive" onClick={() => act(c.id, "reverse")}>{c.status === "paid" ? "Annuler & rembourser" : "Annuler"}</Button>}
          </div>,
        ])}
      />
    </>
  );
}

function ReferralsTable({ rows, groupById, onChanged }: {
  rows: DriverReferral[]; groupById: Record<string, DriverGroup>; onChanged: () => void;
}) {
  if (rows.length === 0) {
    return <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucun parrainage enregistré.</Card>;
  }
  const act = async (id: string, action: "approve" | "mark_eligible" | "mark_paid" | "reject") => {
    try { await markReferral(id, action); toast({ title: "Parrainage mis à jour" }); onChanged(); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };
  return (
    <DataTable
      columns={["Date", "Chauffeur référré", "Groupe", "Code", "Bonus", "Statut", "Actions"]}
      rows={rows.map(r => [
        new Date(r.created_at).toLocaleDateString("fr-FR"),
        <span className="font-mono text-[11px]">{r.referred_driver_user_id.slice(0, 8)}…</span>,
        r.group_id ? (groupById[r.group_id]?.name ?? "—") : "—",
        r.referral_code || "—",
        formatGnf(r.bonus_amount_gnf),
        <StatusBadge status={r.status} />,
        <div className="flex gap-1">
          {r.status === "pending" && <Button size="sm" variant="outline" className="h-6 text-[10px]" onClick={() => act(r.id, "mark_eligible")}>Éligible</Button>}
          {r.status === "bonus_eligible" && <Button size="sm" variant="outline" className="h-6 text-[10px]" onClick={() => act(r.id, "mark_paid")}>Payé</Button>}
          {r.status !== "rejected" && r.status !== "paid" && <Button size="sm" variant="ghost" className="h-6 text-[10px] text-destructive" onClick={() => act(r.id, "reject")}>Rejeter</Button>}
        </div>,
      ])}
    />
  );
}

function CreateGroupSheet({ open, onOpenChange, onCreated, zones }: {
  open: boolean; onOpenChange: (v: boolean) => void; onCreated: () => void; zones: Zone[];
}) {
  const [form, setForm] = useState({
    name: "", leader_name: "", leader_phone: "",
    commission_percent: "1.00", signup_bonus_gnf: "0",
    assigned_zones: "", referral_code: "", notes: "",
  });
  const [zoneIds, setZoneIds] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    if (!form.name.trim()) { toast({ title: "Nom requis", variant: "destructive" }); return; }
    setSaving(true);
    try {
      const zoneNamesFromIds = zones.filter(z => zoneIds.includes(z.id)).map(zoneLabel);
      const freeFormZones = form.assigned_zones.split(",").map(z => z.trim()).filter(Boolean);
      const mergedNames = zoneNamesFromIds.length > 0 ? zoneNamesFromIds : freeFormZones;
      await createDriverGroup({
        name: form.name.trim(),
        leader_name: form.leader_name || null,
        leader_phone: form.leader_phone || null,
        commission_percent: Number(form.commission_percent) || 1,
        signup_bonus_gnf: Number(form.signup_bonus_gnf) || 0,
        assigned_zones: mergedNames,
        assigned_zone_ids: zoneIds,
        referral_code: form.referral_code || null,
        notes: form.notes || null,
      });
      toast({ title: "Groupe créé" });
      setForm({ name: "", leader_name: "", leader_phone: "", commission_percent: "1.00", signup_bonus_gnf: "0", assigned_zones: "", referral_code: "", notes: "" });
      setZoneIds([]);
      onOpenChange(false);
      onCreated();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message, variant: "destructive" });
    } finally { setSaving(false); }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader><SheetTitle>Nouveau groupe chauffeurs</SheetTitle></SheetHeader>
        <div className="space-y-3 mt-4">
          <Field label="Nom du groupe *"><Input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} /></Field>
          <div className="grid grid-cols-2 gap-2">
            <Field label="Nom du leader"><Input value={form.leader_name} onChange={e => setForm(f => ({ ...f, leader_name: e.target.value }))} /></Field>
            <Field label="Téléphone leader"><Input value={form.leader_phone} onChange={e => setForm(f => ({ ...f, leader_phone: e.target.value }))} /></Field>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <Field label="Commission %"><Input type="number" step="0.01" value={form.commission_percent} onChange={e => setForm(f => ({ ...f, commission_percent: e.target.value }))} /></Field>
            <Field label="Bonus signup (GNF)"><Input type="number" value={form.signup_bonus_gnf} onChange={e => setForm(f => ({ ...f, signup_bonus_gnf: e.target.value }))} /></Field>
          </div>
          {zones.length > 0 ? (
            <Field label="Zones (multi-sélection)">
              <div className="flex flex-wrap gap-1 max-h-44 overflow-y-auto p-2 border rounded-md">
                {zones.map(z => {
                  const active = zoneIds.includes(z.id);
                  return (
                    <button key={z.id} type="button"
                      onClick={() => setZoneIds(cur => active ? cur.filter(x => x !== z.id) : [...cur, z.id])}
                      className={`text-[11px] px-2 py-1 rounded-full border ${active ? "bg-primary text-primary-foreground border-primary" : "bg-background border-border"}`}>
                      {zoneLabel(z)}
                    </button>
                  );
                })}
              </div>
            </Field>
          ) : (
            <Field label="Zones (séparées par ,)"><Input placeholder="Kaloum, Dixinn, Ratoma" value={form.assigned_zones} onChange={e => setForm(f => ({ ...f, assigned_zones: e.target.value }))} /></Field>
          )}
          <Field label="Code de référral (optionnel)"><Input value={form.referral_code} onChange={e => setForm(f => ({ ...f, referral_code: e.target.value }))} /></Field>
          <Field label="Notes"><Textarea rows={3} value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} /></Field>
          <Button className="w-full" onClick={submit} disabled={saving}>{saving ? "Création…" : "Créer le groupe"}</Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}

function AssignDriverDialog({ group, onClose, onAssigned, zones }: {
  group: DriverGroup | null; onClose: () => void; onAssigned: () => void; zones: Zone[];
}) {
  const [driverId, setDriverId] = useState("");
  const [zone, setZone] = useState("");
  const [zoneId, setZoneId] = useState<string>("");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const [drivers, setDrivers] = useState<{ user_id: string; status: string }[]>([]);

  useEffect(() => {
    if (!group) return;
    (async () => {
      const { data } = await supabase
        .from("driver_profiles")
        .select("user_id,status")
        .in("status", ["approved", "pending"])
        .order("created_at", { ascending: false })
        .limit(200);
      setDrivers((data ?? []) as any);
    })();
  }, [group]);

  const submit = async () => {
    if (!group || !driverId) return;
    setSaving(true);
    try {
      const z = zones.find(x => x.id === zoneId);
      const zoneName = z ? zoneLabel(z) : (zone || null);
      await assignDriverToGroup(group.id, driverId, zoneName, notes || null);
      toast({ title: "Chauffeur assigné" });
      setDriverId(""); setZone(""); setZoneId(""); setNotes("");
      onClose(); onAssigned();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message, variant: "destructive" });
    } finally { setSaving(false); }
  };

  return (
    <Dialog open={!!group} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>Assigner un chauffeur · {group?.name}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <Field label="Chauffeur (user_id ou choix)">
            <select className="w-full h-9 rounded-md border border-input bg-background px-2 text-sm"
              value={driverId} onChange={(e) => setDriverId(e.target.value)}>
              <option value="">— Sélectionner —</option>
              {drivers.map(d => <option key={d.user_id} value={d.user_id}>{d.user_id.slice(0, 8)}… ({d.status})</option>)}
            </select>
          </Field>
          {zones.length > 0 ? (
            <Field label="Zone assignée">
              <select className="w-full h-9 rounded-md border border-input bg-background px-2 text-sm"
                value={zoneId} onChange={(e) => setZoneId(e.target.value)}>
                <option value="">— Aucune —</option>
                {zones.map(z => <option key={z.id} value={z.id}>{zoneLabel(z)}</option>)}
              </select>
            </Field>
          ) : (
            <Field label="Zone assignée"><Input value={zone} onChange={e => setZone(e.target.value)} placeholder="Kaloum, Dixinn…" /></Field>
          )}
          <Field label="Notes"><Textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} /></Field>
          <Button className="w-full" onClick={submit} disabled={!driverId || saving}>{saving ? "Assignation…" : "Assigner"}</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <Label className="text-xs">{label}</Label>
      {children}
    </div>
  );
}

function AnalyticsPanel({ groupById }: { groupById: Record<string, DriverGroup> }) {
  const [rows, setRows] = useState<DriverGroupStats[]>([]);
  const [loading, setLoading] = useState(true);
  const [days, setDays] = useState(30);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    const from = new Date(Date.now() - days * 86_400_000);
    adminDriverGroupStats({ from, to: new Date() })
      .then((r) => { if (!cancelled) setRows(r); })
      .catch((e: any) => toast({ title: "Erreur analytics", description: e?.message, variant: "destructive" }))
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [days]);

  const totals = useMemo(() => rows.reduce((acc, r) => ({
    active_drivers: acc.active_drivers + Number(r.active_drivers || 0),
    rides_completed: acc.rides_completed + Number(r.rides_completed || 0),
    gross: acc.gross + Number(r.gross_driver_earnings_gnf || 0),
    pending: acc.pending + Number(r.commissions_pending_gnf || 0),
    paid: acc.paid + Number(r.commissions_paid_gnf || 0),
    bonus_eligible: acc.bonus_eligible + Number(r.signup_bonus_eligible_count || 0),
    bonus_paid: acc.bonus_paid + Number(r.signup_bonus_paid_gnf || 0),
  }), { active_drivers: 0, rides_completed: 0, gross: 0, pending: 0, paid: 0, bonus_eligible: 0, bonus_paid: 0 }), [rows]);

  return (
    <div className="space-y-3">
      <div className="flex gap-2 items-center">
        <Label className="text-xs">Période :</Label>
        {[7, 30, 90].map(d => (
          <FilterChip key={d} label={`${d} j`} active={days === d} onClick={() => setDays(d)} />
        ))}
      </div>
      <StatGrid items={[
        { label: "Chauffeurs actifs", value: loading ? "…" : String(totals.active_drivers), icon: Users2 },
        { label: "Courses terminées", value: loading ? "…" : String(totals.rides_completed), icon: Coins },
        { label: "Gains chauffeurs", value: loading ? "…" : formatGnf(totals.gross), icon: Coins },
        { label: "Commissions payées", value: loading ? "…" : formatGnf(totals.paid), icon: Coins },
      ]} />
      {loading ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Chargement…</Card>
      ) : rows.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucune donnée sur la période.</Card>
      ) : (
        <DataTable
          columns={["Groupe", "Chauffeurs actifs", "Courses", "Gains chauffeurs", "Commissions en attente", "Commissions payées", "Bonus éligibles", "Bonus payés"]}
          rows={rows.map(r => [
            groupById[r.group_id]?.name ?? "—",
            String(r.active_drivers),
            String(r.rides_completed),
            formatGnf(r.gross_driver_earnings_gnf),
            formatGnf(r.commissions_pending_gnf),
            formatGnf(r.commissions_paid_gnf),
            String(r.signup_bonus_eligible_count),
            formatGnf(r.signup_bonus_paid_gnf),
          ])}
        />
      )}
    </div>
  );
}