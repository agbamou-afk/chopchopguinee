import { useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/hooks/use-toast";
import type { DriverGroup } from "@/lib/admin/driverGroups";
import {
  listMilestoneJobs, processMilestoneJobs, enqueueMilestoneRefresh,
  adminListCheckins, listRiskReviews,
  type MilestoneJob, type FieldCheckin, type RiskReview,
} from "@/lib/admin/driverGroupsV4";

export function MilestoneJobsPanel() {
  const [jobs, setJobs] = useState<MilestoneJob[]>([]);
  const [loading, setLoading] = useState(true);
  const [running, setRunning] = useState(false);
  const [filter, setFilter] = useState<string>("");
  const [enqueueId, setEnqueueId] = useState("");

  const reload = async () => {
    setLoading(true);
    try { setJobs(await listMilestoneJobs(filter || undefined)); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
    finally { setLoading(false); }
  };
  useEffect(() => { reload(); }, [filter]);

  const run = async () => {
    setRunning(true);
    try {
      const r = await processMilestoneJobs(50);
      toast({ title: "Jalons traités", description: `Traités ${r?.processed ?? 0} · Éligibles +${r?.eligible ?? 0} · Échecs ${r?.failed ?? 0}` });
      reload();
    } catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
    finally { setRunning(false); }
  };

  const enqueue = async () => {
    if (!enqueueId.trim()) return;
    try {
      await enqueueMilestoneRefresh(enqueueId.trim());
      toast({ title: "Job ajouté" });
      setEnqueueId(""); reload();
    } catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
  };

  const counts = {
    pending: jobs.filter(j => j.status === "pending").length,
    processing: jobs.filter(j => j.status === "processing").length,
    failed: jobs.filter(j => j.status === "failed").length,
    processed: jobs.filter(j => j.status === "processed").length,
  };

  return (
    <div className="space-y-3">
      <Card className="p-4 space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold">Jalons de parrainage (jobs)</h3>
          <Button size="sm" disabled={running} onClick={run}>
            {running ? "Traitement…" : "Actualiser les jalons"}
          </Button>
        </div>
        <div className="grid grid-cols-4 gap-2 text-[11px]">
          <div className="border border-border/40 rounded p-2"><span className="text-muted-foreground">En attente</span><p className="font-semibold tabular-nums">{counts.pending}</p></div>
          <div className="border border-border/40 rounded p-2"><span className="text-muted-foreground">En cours</span><p className="font-semibold tabular-nums">{counts.processing}</p></div>
          <div className="border border-border/40 rounded p-2"><span className="text-muted-foreground">Traités</span><p className="font-semibold tabular-nums">{counts.processed}</p></div>
          <div className="border border-border/40 rounded p-2"><span className="text-muted-foreground">Échecs</span><p className="font-semibold tabular-nums">{counts.failed}</p></div>
        </div>
        <div className="flex flex-wrap gap-2">
          {["", "pending", "processing", "processed", "failed"].map(s => (
            <button key={s || "all"} onClick={() => setFilter(s)}
              className={`text-[11px] px-2 py-1 rounded border ${filter === s ? "bg-primary text-primary-foreground border-primary" : "bg-background border-border text-muted-foreground"}`}>
              {s || "tous"}
            </button>
          ))}
        </div>
        <div className="flex gap-2">
          <Input placeholder="driver_user_id à reprogrammer" value={enqueueId} onChange={e => setEnqueueId(e.target.value)} />
          <Button size="sm" variant="outline" onClick={enqueue}>Ajouter job</Button>
        </div>
      </Card>

      <Card className="p-3 space-y-1">
        {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
          : jobs.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucun job.</p>
          : jobs.map(j => (
            <div key={j.id} className="flex justify-between text-[12px] border-b border-border/40 pb-1">
              <div>
                <p className="font-mono">{(j.driver_user_id ?? "—").slice(0,8)}… · {j.event_type}</p>
                <p className="text-[10px] text-muted-foreground">{new Date(j.created_at).toLocaleString("fr-FR")} · tentatives {j.attempts} {j.last_error ? `· ${j.last_error}` : ""}</p>
              </div>
              <span className={`text-[10px] px-1.5 py-0.5 rounded h-fit ${
                j.status === "failed" ? "bg-destructive/15 text-destructive"
                : j.status === "processed" ? "bg-primary/15 text-primary"
                : "bg-muted"}`}>{j.status}</span>
            </div>
          ))}
      </Card>
    </div>
  );
}

export function FieldCheckinsPanel({ groups }: { groups: DriverGroup[] }) {
  const [rows, setRows] = useState<FieldCheckin[]>([]);
  const [loading, setLoading] = useState(true);
  const [groupId, setGroupId] = useState<string>("");

  const reload = async () => {
    setLoading(true);
    try { setRows(await adminListCheckins(groupId || null)); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
    finally { setLoading(false); }
  };
  useEffect(() => { reload(); }, [groupId]);

  const groupName = (id: string) => groups.find(g => g.id === id)?.name ?? id.slice(0,8);

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-semibold">Check-ins terrain</h3>
        <select className="bg-background border border-border rounded text-xs h-8 px-2"
          value={groupId} onChange={e => setGroupId(e.target.value)}>
          <option value="">Tous les groupes</option>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucun check-in pour l'instant.</p>
        : rows.map(c => (
          <div key={c.id} className="border border-border/40 rounded p-2 text-sm space-y-1">
            <div className="flex justify-between">
              <p className="font-medium text-[12px]">{groupName(c.group_id)} · {c.checkin_type}</p>
              <span className="text-[10px] text-muted-foreground">{new Date(c.created_at).toLocaleString("fr-FR")}</span>
            </div>
            {c.notes && <p className="text-[11px] text-muted-foreground">{c.notes}</p>}
            {(c.lat && c.lng) && (
              <p className="text-[10px] text-muted-foreground tabular-nums">
                {c.lat.toFixed(5)}, {c.lng.toFixed(5)}{c.accuracy_m ? ` · ±${Math.round(c.accuracy_m)}m` : ""}
              </p>
            )}
          </div>
        ))}
      <p className="text-[10px] text-muted-foreground pt-2 border-t border-border/40">
        Records opérationnels. Pas de suivi continu — les leaders déclarent ponctuellement.
      </p>
    </Card>
  );
}

export function RiskAuditPanel() {
  const [rows, setRows] = useState<RiskReview[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try { setRows(await listRiskReviews()); }
      catch (e: any) { toast({ title: "Erreur", description: e?.message, variant: "destructive" }); }
      finally { setLoading(false); }
    })();
  }, []);
  return (
    <Card className="p-4 space-y-2">
      <h3 className="text-sm font-semibold">Historique des décisions risque</h3>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucune décision enregistrée.</p>
        : rows.map(r => (
          <div key={r.id} className="text-[12px] border-b border-border/40 pb-1">
            <p>{r.entity_type} <span className="font-mono">{r.entity_id.slice(0,8)}</span> → <strong>{r.status}</strong></p>
            <p className="text-[10px] text-muted-foreground">{new Date(r.reviewed_at).toLocaleString("fr-FR")} · {r.reason ?? "—"}</p>
          </div>
        ))}
    </Card>
  );
}