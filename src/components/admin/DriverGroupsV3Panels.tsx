import { useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { toast } from "@/hooks/use-toast";
import { formatGnf, type DriverGroup, type DriverGroupCommission, type DriverReferral } from "@/lib/admin/driverGroups";
import {
  listCampaigns, createCampaign, updateCampaign,
  listContracts, createContract,
  listStatements, listStatementItems, generateStatement, setStatementStatus, downloadStatementCsv,
  reviewReferralRisk, reviewCommissionRisk, scoreReferralRisk,
  zoneCoverageStats,
  type RecruitmentCampaign, type GroupContract, type PayoutStatement, type PayoutStatementItem, type ZoneCoverageRow,
} from "@/lib/admin/driverGroupsV3";

/* ----------------------------- Campaigns ----------------------------- */

export function CampaignsPanel({ groups, onChanged }: { groups: DriverGroup[]; onChanged?: () => void }) {
  const [rows, setRows] = useState<RecruitmentCampaign[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);

  const reload = async () => {
    setLoading(true);
    try { setRows(await listCampaigns()); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
    finally { setLoading(false); }
  };
  useEffect(() => { reload(); }, []);

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Campagnes de recrutement</h3>
        <Sheet open={open} onOpenChange={setOpen}>
          <SheetTrigger asChild><Button size="sm">Nouvelle campagne</Button></SheetTrigger>
          <SheetContent className="w-full sm:max-w-md overflow-y-auto">
            <SheetHeader><SheetTitle>Nouvelle campagne</SheetTitle></SheetHeader>
            <CampaignForm groups={groups} onSaved={() => { setOpen(false); reload(); onChanged?.(); }} />
          </SheetContent>
        </Sheet>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucune campagne pour l'instant.</p>
        : rows.map(c => (
          <div key={c.id} className="border border-border/40 rounded p-3 text-sm space-y-1">
            <div className="flex items-center justify-between">
              <p className="font-medium">{c.name}</p>
              <select
                className="text-[11px] bg-background border border-border rounded px-1 py-0.5"
                value={c.status}
                onChange={async (e) => {
                  try { await updateCampaign(c.id, { status: e.target.value }); toast({ title: "Statut mis à jour" }); reload(); }
                  catch (err: any) { toast({ title: "Erreur", description: err?.message, variant: "destructive" }); }
                }}>
                {["draft","active","paused","completed","cancelled"].map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Groupe: {groups.find(g => g.id === c.group_id)?.name ?? c.group_id.slice(0,8)} ·
              Cible: {c.target_driver_count} chauffeurs / {c.target_completed_rides} courses ·
              Bonus: {formatGnf(c.signup_bonus_gnf)} · Règle: {c.milestone_rule}
            </p>
            {(c.start_date || c.end_date) && (
              <p className="text-[11px] text-muted-foreground">Période: {c.start_date ?? "—"} → {c.end_date ?? "—"}</p>
            )}
          </div>
        ))}
    </Card>
  );
}

function CampaignForm({ groups, onSaved }: { groups: DriverGroup[]; onSaved: () => void }) {
  const [form, setForm] = useState({
    group_id: groups[0]?.id ?? "",
    name: "", description: "",
    target_driver_count: 0, target_active_driver_count: 0, target_completed_rides: 0,
    start_date: "", end_date: "",
    signup_bonus_gnf: 0, milestone_rule: "approved" as const,
  });
  const submit = async () => {
    if (!form.group_id || !form.name.trim()) {
      toast({ title: "Groupe et nom requis", variant: "destructive" }); return;
    }
    try {
      await createCampaign(form as any);
      toast({ title: "Campagne créée" });
      onSaved();
    } catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };
  return (
    <div className="space-y-3 mt-4">
      <div>
        <Label>Groupe</Label>
        <select className="w-full mt-1 bg-background border border-border rounded h-9 px-2 text-sm"
          value={form.group_id} onChange={e => setForm({ ...form, group_id: e.target.value })}>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
      </div>
      <div><Label>Nom</Label><Input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></div>
      <div><Label>Description</Label><Textarea value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></div>
      <div className="grid grid-cols-3 gap-2">
        <div><Label className="text-[11px]">Chauffeurs cible</Label><Input type="number" value={form.target_driver_count} onChange={e => setForm({ ...form, target_driver_count: Number(e.target.value) })} /></div>
        <div><Label className="text-[11px]">Actifs cible</Label><Input type="number" value={form.target_active_driver_count} onChange={e => setForm({ ...form, target_active_driver_count: Number(e.target.value) })} /></div>
        <div><Label className="text-[11px]">Courses cible</Label><Input type="number" value={form.target_completed_rides} onChange={e => setForm({ ...form, target_completed_rides: Number(e.target.value) })} /></div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div><Label className="text-[11px]">Début</Label><Input type="date" value={form.start_date} onChange={e => setForm({ ...form, start_date: e.target.value })} /></div>
        <div><Label className="text-[11px]">Fin</Label><Input type="date" value={form.end_date} onChange={e => setForm({ ...form, end_date: e.target.value })} /></div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div><Label className="text-[11px]">Bonus signup (GNF)</Label><Input type="number" value={form.signup_bonus_gnf} onChange={e => setForm({ ...form, signup_bonus_gnf: Number(e.target.value) })} /></div>
        <div>
          <Label className="text-[11px]">Règle palier</Label>
          <select className="w-full mt-1 bg-background border border-border rounded h-9 px-2 text-sm"
            value={form.milestone_rule}
            onChange={e => setForm({ ...form, milestone_rule: e.target.value as any })}>
            <option value="approved">Approuvé</option>
            <option value="first_ride_completed">1ère course</option>
            <option value="five_rides_completed">5 courses</option>
            <option value="seven_days_active">7 jours actif</option>
          </select>
        </div>
      </div>
      <Button className="w-full" onClick={submit}>Créer</Button>
    </div>
  );
}

/* ----------------------------- Contracts ----------------------------- */

export function ContractsPanel({ groups }: { groups: DriverGroup[] }) {
  const [rows, setRows] = useState<GroupContract[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);

  const reload = async () => {
    setLoading(true);
    try { setRows(await listContracts()); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
    finally { setLoading(false); }
  };
  useEffect(() => { reload(); }, []);

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Contrats de performance</h3>
        <Sheet open={open} onOpenChange={setOpen}>
          <SheetTrigger asChild><Button size="sm">Nouveau contrat</Button></SheetTrigger>
          <SheetContent className="w-full sm:max-w-md overflow-y-auto">
            <SheetHeader><SheetTitle>Nouveau contrat</SheetTitle></SheetHeader>
            <ContractForm groups={groups} onSaved={() => { setOpen(false); reload(); }} />
          </SheetContent>
        </Sheet>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucun contrat enregistré.</p>
        : rows.map(c => (
          <div key={c.id} className="border border-border/40 rounded p-3 text-sm space-y-1">
            <div className="flex justify-between">
              <p className="font-medium">{c.name}</p>
              <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{c.status}</span>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Groupe: {groups.find(g => g.id === c.group_id)?.name ?? c.group_id.slice(0,8)} ·
              Cibles: {c.target_driver_count} chauffeurs · {c.target_completed_rides} courses · {formatGnf(c.target_gross_earnings_gnf)}
            </p>
            <p className="text-[11px] text-muted-foreground">Période: {c.period_start ?? "—"} → {c.period_end ?? "—"}</p>
          </div>
        ))}
    </Card>
  );
}

function ContractForm({ groups, onSaved }: { groups: DriverGroup[]; onSaved: () => void }) {
  const [form, setForm] = useState({
    group_id: groups[0]?.id ?? "", name: "",
    period_start: "", period_end: "",
    target_driver_count: 0, target_active_driver_count: 0,
    target_completed_rides: 0, target_gross_earnings_gnf: 0,
    terms: "",
  });
  const submit = async () => {
    if (!form.group_id || !form.name.trim()) { toast({ title: "Groupe et nom requis", variant: "destructive" }); return; }
    try { await createContract(form as any); toast({ title: "Contrat créé" }); onSaved(); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };
  return (
    <div className="space-y-3 mt-4">
      <div>
        <Label>Groupe</Label>
        <select className="w-full mt-1 bg-background border border-border rounded h-9 px-2 text-sm"
          value={form.group_id} onChange={e => setForm({ ...form, group_id: e.target.value })}>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
      </div>
      <div><Label>Nom</Label><Input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></div>
      <div className="grid grid-cols-2 gap-2">
        <div><Label className="text-[11px]">Début</Label><Input type="date" value={form.period_start} onChange={e => setForm({ ...form, period_start: e.target.value })} /></div>
        <div><Label className="text-[11px]">Fin</Label><Input type="date" value={form.period_end} onChange={e => setForm({ ...form, period_end: e.target.value })} /></div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div><Label className="text-[11px]">Chauffeurs cible</Label><Input type="number" value={form.target_driver_count} onChange={e => setForm({ ...form, target_driver_count: Number(e.target.value) })} /></div>
        <div><Label className="text-[11px]">Actifs cible</Label><Input type="number" value={form.target_active_driver_count} onChange={e => setForm({ ...form, target_active_driver_count: Number(e.target.value) })} /></div>
        <div><Label className="text-[11px]">Courses cible</Label><Input type="number" value={form.target_completed_rides} onChange={e => setForm({ ...form, target_completed_rides: Number(e.target.value) })} /></div>
        <div><Label className="text-[11px]">Revenus cible (GNF)</Label><Input type="number" value={form.target_gross_earnings_gnf} onChange={e => setForm({ ...form, target_gross_earnings_gnf: Number(e.target.value) })} /></div>
      </div>
      <div><Label className="text-[11px]">Termes</Label><Textarea value={form.terms} onChange={e => setForm({ ...form, terms: e.target.value })} /></div>
      <Button className="w-full" onClick={submit}>Créer</Button>
    </div>
  );
}

/* --------------------------- Payout statements --------------------------- */

export function StatementsPanel({ groups }: { groups: DriverGroup[] }) {
  const [rows, setRows] = useState<PayoutStatement[]>([]);
  const [loading, setLoading] = useState(true);
  const [genOpen, setGenOpen] = useState(false);
  const [selected, setSelected] = useState<PayoutStatement | null>(null);
  const [items, setItems] = useState<PayoutStatementItem[]>([]);

  const reload = async () => {
    setLoading(true);
    try { setRows(await listStatements()); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
    finally { setLoading(false); }
  };
  useEffect(() => { reload(); }, []);

  const openStatement = async (s: PayoutStatement) => {
    setSelected(s);
    try { setItems(await listStatementItems(s.id)); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Relevés de paiement</h3>
        <Sheet open={genOpen} onOpenChange={setGenOpen}>
          <SheetTrigger asChild><Button size="sm">Générer un relevé</Button></SheetTrigger>
          <SheetContent className="w-full sm:max-w-md">
            <SheetHeader><SheetTitle>Générer un relevé</SheetTitle></SheetHeader>
            <StatementGenerateForm groups={groups} onSaved={() => { setGenOpen(false); reload(); }} />
          </SheetContent>
        </Sheet>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucun relevé.</p>
        : rows.map(s => (
          <div key={s.id} className="border border-border/40 rounded p-3 text-sm space-y-1">
            <div className="flex justify-between gap-2">
              <div>
                <p className="font-medium">{groups.find(g => g.id === s.group_id)?.name ?? s.group_id.slice(0,8)}</p>
                <p className="text-[11px] text-muted-foreground">{s.period_start} → {s.period_end} · {s.status}</p>
              </div>
              <div className="text-right">
                <p className="font-medium tabular-nums">{formatGnf(s.total_due_gnf)}</p>
                <p className="text-[10px] text-muted-foreground">Comm. {formatGnf(s.commissions_total_gnf)} · Bonus {formatGnf(s.signup_bonuses_total_gnf)}</p>
              </div>
            </div>
            <div className="flex flex-wrap gap-2 pt-1">
              <Button size="sm" variant="outline" onClick={() => openStatement(s)}>Détails</Button>
              {s.status === "draft" && (
                <Button size="sm" variant="outline" onClick={async () => { await setStatementStatus(s.id, "finalized"); toast({ title: "Relevé finalisé" }); reload(); }}>Finaliser</Button>
              )}
              {s.status === "finalized" && (
                <Button size="sm" variant="outline" onClick={async () => {
                  try { await setStatementStatus(s.id, "paid"); toast({ title: "Relevé marqué payé" }); reload(); }
                  catch (e: any) { toast({ title: "Impossible", description: e?.message, variant: "destructive" }); }
                }}>Marquer payé</Button>
              )}
              {s.status !== "void" && s.status !== "paid" && (
                <Button size="sm" variant="ghost" onClick={async () => { await setStatementStatus(s.id, "void"); toast({ title: "Relevé annulé" }); reload(); }}>Annuler</Button>
              )}
            </div>
          </div>
        ))}

      {selected && (
        <Sheet open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
          <SheetContent className="w-full sm:max-w-lg overflow-y-auto">
            <SheetHeader><SheetTitle>Détails du relevé</SheetTitle></SheetHeader>
            <div className="mt-3 space-y-2">
              <Button size="sm" variant="outline" onClick={() => downloadStatementCsv(selected, items)}>
                Télécharger CSV
              </Button>
              {items.length === 0 ? <p className="text-sm text-muted-foreground">Aucune ligne.</p>
                : items.map(i => (
                  <div key={i.id} className="flex justify-between text-sm border-b border-border/40 pb-1">
                    <div>
                      <p className="text-[11px]">{i.item_type}</p>
                      <p className="text-[10px] text-muted-foreground truncate">{i.description}</p>
                    </div>
                    <p className="tabular-nums">{formatGnf(i.amount_gnf)}</p>
                  </div>
                ))}
            </div>
          </SheetContent>
        </Sheet>
      )}
    </Card>
  );
}

function StatementGenerateForm({ groups, onSaved }: { groups: DriverGroup[]; onSaved: () => void }) {
  const today = new Date().toISOString().slice(0, 10);
  const monthAgo = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
  const [form, setForm] = useState({ group_id: groups[0]?.id ?? "", from: monthAgo, to: today, notes: "" });
  const submit = async () => {
    if (!form.group_id) return;
    try { await generateStatement(form.group_id, form.from, form.to, form.notes); toast({ title: "Relevé généré" }); onSaved(); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };
  return (
    <div className="space-y-3 mt-4">
      <div>
        <Label>Groupe</Label>
        <select className="w-full mt-1 bg-background border border-border rounded h-9 px-2 text-sm"
          value={form.group_id} onChange={e => setForm({ ...form, group_id: e.target.value })}>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div><Label className="text-[11px]">Du</Label><Input type="date" value={form.from} onChange={e => setForm({ ...form, from: e.target.value })} /></div>
        <div><Label className="text-[11px]">Au</Label><Input type="date" value={form.to} onChange={e => setForm({ ...form, to: e.target.value })} /></div>
      </div>
      <div><Label className="text-[11px]">Notes</Label><Textarea value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} /></div>
      <Button className="w-full" onClick={submit}>Générer</Button>
    </div>
  );
}

/* ----------------------------- Risk queue ----------------------------- */

export function RiskQueuePanel({
  referrals, commissions, onChanged,
}: {
  referrals: DriverReferral[]; commissions: DriverGroupCommission[]; onChanged: () => void;
}) {
  const flaggedRefs = referrals.filter(r => (r as any).risk_status && (r as any).risk_status !== "clear");
  const flaggedComms = commissions.filter(c => (c as any).risk_status && (c as any).risk_status !== "clear");

  const scoreOne = async (id: string) => {
    try {
      const res = await scoreReferralRisk(id);
      if (res) {
        await reviewReferralRisk(id, res.status === "held" ? "hold" : res.status === "review" ? "review" : "clear", res.reason || undefined);
        toast({ title: `Score ${res.score} · ${res.status}`, description: res.reason || "Aucun signal" });
        onChanged();
      }
    } catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };

  return (
    <div className="space-y-3">
      <Card className="p-4 space-y-2">
        <h3 className="text-sm font-semibold">Contrôle risque — Parrainages</h3>
        <p className="text-[11px] text-muted-foreground">
          Les signalements ne sanctionnent jamais automatiquement; un admin doit confirmer ou rejeter.
        </p>
        {flaggedRefs.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-3">Aucun parrainage signalé.</p>
        ) : flaggedRefs.map(r => {
          const meta = r as any;
          return (
            <div key={r.id} className="border border-border/40 rounded p-2 text-sm space-y-1">
              <div className="flex justify-between">
                <p className="font-mono text-[11px]">{r.referred_driver_user_id.slice(0,8)}…</p>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-destructive/15 text-destructive">{meta.risk_status}</span>
              </div>
              <p className="text-[11px] text-muted-foreground">{meta.risk_reason || "—"}</p>
              <div className="flex gap-2">
                <Button size="sm" variant="outline" onClick={async () => { await reviewReferralRisk(r.id, "clear"); toast({ title: "Effacé" }); onChanged(); }}>Effacer</Button>
                <Button size="sm" variant="outline" onClick={async () => { await reviewReferralRisk(r.id, "hold"); toast({ title: "En attente" }); onChanged(); }}>Retenir</Button>
                <Button size="sm" variant="ghost" onClick={async () => { await reviewReferralRisk(r.id, "reject"); toast({ title: "Rejeté" }); onChanged(); }}>Rejeter</Button>
              </div>
            </div>
          );
        })}
      </Card>

      <Card className="p-4 space-y-2">
        <h3 className="text-sm font-semibold">Contrôle risque — Commissions</h3>
        {flaggedComms.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-3">Aucune commission signalée.</p>
        ) : flaggedComms.map(c => {
          const meta = c as any;
          return (
            <div key={c.id} className="border border-border/40 rounded p-2 text-sm space-y-1">
              <div className="flex justify-between">
                <p className="tabular-nums">{formatGnf(c.commission_amount_gnf)} · {c.source_type}</p>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-destructive/15 text-destructive">{meta.risk_status}</span>
              </div>
              <p className="text-[11px] text-muted-foreground">{meta.risk_reason || "—"}</p>
              <div className="flex gap-2">
                <Button size="sm" variant="outline" onClick={async () => { await reviewCommissionRisk(c.id, "clear"); toast({ title: "Effacé" }); onChanged(); }}>Effacer</Button>
                <Button size="sm" variant="outline" onClick={async () => { await reviewCommissionRisk(c.id, "hold"); toast({ title: "En attente" }); onChanged(); }}>Retenir</Button>
                <Button size="sm" variant="ghost" onClick={async () => { await reviewCommissionRisk(c.id, "reject"); toast({ title: "Rejetée" }); onChanged(); }}>Rejeter</Button>
              </div>
            </div>
          );
        })}
      </Card>

      <Card className="p-4 space-y-2">
        <h3 className="text-sm font-semibold">Lancer un score</h3>
        <p className="text-[11px] text-muted-foreground">Calcule un score de risque pour un parrainage donné (ID).</p>
        <ScoreOneForm onScore={scoreOne} />
      </Card>
    </div>
  );
}

function ScoreOneForm({ onScore }: { onScore: (id: string) => Promise<void> }) {
  const [id, setId] = useState("");
  return (
    <div className="flex gap-2">
      <Input placeholder="referral_id" value={id} onChange={e => setId(e.target.value)} />
      <Button size="sm" onClick={() => id && onScore(id.trim())}>Scorer</Button>
    </div>
  );
}

/* --------------------------- Zone coverage --------------------------- */

export function ZoneCoveragePanel() {
  const [rows, setRows] = useState<ZoneCoverageRow[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try { setRows(await zoneCoverageStats()); }
      catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
      finally { setLoading(false); }
    })();
  }, []);

  return (
    <Card className="p-4 space-y-2">
      <h3 className="text-sm font-semibold">Couverture des zones</h3>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucune zone configurée.</p>
        : (
          <div className="space-y-1">
            {rows.map(z => (
              <div key={z.zone_id} className="flex justify-between text-sm border-b border-border/40 pb-1">
                <p>{z.zone_label}</p>
                <p className="text-[11px] text-muted-foreground tabular-nums">
                  {z.active_drivers_count}/{z.drivers_count} actifs · {z.groups_count} groupes
                </p>
              </div>
            ))}
          </div>
        )}
      <p className="text-[10px] text-muted-foreground pt-2">
        Couverture basée sur les zones assignées aux groupes et aux membres. Le mapping par polygones pickup/dropoff arrive en v4.
      </p>
    </Card>
  );
}