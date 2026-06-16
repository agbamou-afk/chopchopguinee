import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/lib/toast";
import {
  listPilots, upsertPilot, setPilotStatus, listAssignments, createAssignment,
  updateAssignmentStatus, listVisits, listReports, setReportStatus,
  type FieldPilotStatus, VISIT_STATUS_LABEL, REPORT_STATUS_LABEL, INTEREST_LABEL,
  type FieldAssignmentRole,
} from "@/lib/maps/field";
import { supabase } from "@/integrations/supabase/client";

const STATUSES: FieldPilotStatus[] = ["planned", "active", "paused", "completed", "cancelled"];

export default function FieldPilotsAdmin() {
  const [pilots, setPilots] = useState<any[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [assignments, setAssignments] = useState<any[]>([]);
  const [visits, setVisits] = useState<any[]>([]);
  const [reports, setReports] = useState<any[]>([]);
  const [form, setForm] = useState({ name: "", description: "", target_merchant_count: 50, start_date: "", end_date: "" });
  const [assignForm, setAssignForm] = useState<{ user_id: string; role: FieldAssignmentRole; zone_id: string }>({
    user_id: "", role: "field_agent", zone_id: "",
  });
  const [me, setMe] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setMe(data.user?.id ?? null));
    refresh();
  }, []);
  useEffect(() => { if (selected) loadDetail(selected); }, [selected]);

  async function refresh() {
    try { setPilots(await listPilots()); } catch (e: any) { toast.error(e.message); }
  }
  async function loadDetail(id: string) {
    try {
      const [a, v, r] = await Promise.all([listAssignments(id), listVisits(id), listReports(id)]);
      setAssignments(a); setVisits(v); setReports(r);
    } catch (e: any) { toast.error(e.message); }
  }

  async function onCreate() {
    if (!form.name.trim()) return toast.error("Nom requis");
    try {
      await upsertPilot({
        name: form.name.trim(),
        description: form.description || null,
        target_merchant_count: Number(form.target_merchant_count) || 0,
        start_date: form.start_date || null,
        end_date: form.end_date || null,
      });
      toast.success("Pilote créé");
      setForm({ name: "", description: "", target_merchant_count: 50, start_date: "", end_date: "" });
      refresh();
    } catch (e: any) { toast.error(e.message); }
  }

  async function onAssign() {
    if (!selected || !assignForm.user_id.trim()) return toast.error("user_id requis");
    try {
      await createAssignment({
        pilot_id: selected,
        user_id: assignForm.user_id.trim(),
        role: assignForm.role,
        assigned_zone_id: assignForm.zone_id.trim() || null,
      });
      toast.success("Assigné");
      setAssignForm({ user_id: "", role: "field_agent", zone_id: "" });
      loadDetail(selected);
    } catch (e: any) { toast.error(e.message); }
  }

  const stats = (() => {
    const submitted = visits.filter(v => v.visit_status === "submitted").length;
    const interested = visits.filter(v => v.interest_level === "interested" || v.interest_level === "signed_up").length;
    const converted = visits.filter(v => v.visit_status === "converted").length;
    const needsReview = visits.filter(v => v.visit_status === "needs_review" || v.visit_status === "duplicate_possible").length;
    const zones = new Set(visits.map(v => v.map_service_zone_id).filter(Boolean)).size;
    return { total: visits.length, submitted, interested, converted, needsReview, zones, reports: reports.length };
  })();

  return (
    <div className="space-y-6 p-4">
      <header>
        <h1 className="text-2xl font-semibold">Pilot terrain</h1>
        <p className="text-sm text-muted-foreground">Sprints de terrain, captains, agents, visites marchands.</p>
      </header>

      <Card>
        <CardHeader><CardTitle>Créer un sprint</CardTitle></CardHeader>
        <CardContent className="grid gap-3 md:grid-cols-5">
          <div><Label>Nom</Label><Input value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></div>
          <div><Label>Objectif marchands</Label><Input type="number" value={form.target_merchant_count} onChange={e=>setForm({...form,target_merchant_count:Number(e.target.value)})}/></div>
          <div><Label>Début</Label><Input type="date" value={form.start_date} onChange={e=>setForm({...form,start_date:e.target.value})}/></div>
          <div><Label>Fin</Label><Input type="date" value={form.end_date} onChange={e=>setForm({...form,end_date:e.target.value})}/></div>
          <div className="flex items-end"><Button onClick={onCreate}>Créer</Button></div>
          <div className="md:col-span-5"><Label>Description</Label><Textarea value={form.description} onChange={e=>setForm({...form,description:e.target.value})}/></div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Sprints</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          {pilots.length === 0 && <p className="text-sm text-muted-foreground">Aucun sprint.</p>}
          {pilots.map(p => (
            <div key={p.id} className={`flex flex-wrap gap-2 items-center justify-between border rounded p-3 ${selected===p.id?"bg-muted":""}`}>
              <div onClick={()=>setSelected(p.id)} className="cursor-pointer flex-1 min-w-[200px]">
                <div className="font-medium">{p.name}</div>
                <div className="text-xs text-muted-foreground">{p.start_date ?? "—"} → {p.end_date ?? "—"} · objectif {p.target_merchant_count}</div>
              </div>
              <Badge>{p.status}</Badge>
              <div className="flex gap-1">
                {STATUSES.map(s => (
                  <Button key={s} size="sm" variant={p.status===s?"default":"outline"}
                    onClick={async()=>{await setPilotStatus(p.id,s); refresh();}}>{s}</Button>
                ))}
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      {selected && (
        <>
          <Card>
            <CardHeader><CardTitle>Résumé du sprint</CardTitle></CardHeader>
            <CardContent className="grid grid-cols-2 md:grid-cols-7 gap-3 text-center">
              <Stat label="Visites" value={stats.total}/>
              <Stat label="Soumises" value={stats.submitted}/>
              <Stat label="Intéressés" value={stats.interested}/>
              <Stat label="Convertis" value={stats.converted}/>
              <Stat label="À revoir" value={stats.needsReview}/>
              <Stat label="Zones couvertes" value={stats.zones}/>
              <Stat label="Rapports" value={stats.reports}/>
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>Assigner captain / agent</CardTitle></CardHeader>
            <CardContent className="grid gap-3 md:grid-cols-4">
              <div><Label>User ID</Label><Input value={assignForm.user_id} onChange={e=>setAssignForm({...assignForm,user_id:e.target.value})}/></div>
              <div>
                <Label>Rôle</Label>
                <select className="w-full border rounded h-10 px-2" value={assignForm.role} onChange={e=>setAssignForm({...assignForm,role:e.target.value as any})}>
                  <option value="field_captain">Captain</option>
                  <option value="field_agent">Agent</option>
                  <option value="verifier">Vérificateur</option>
                </select>
              </div>
              <div><Label>Zone ID (optionnel)</Label><Input value={assignForm.zone_id} onChange={e=>setAssignForm({...assignForm,zone_id:e.target.value})}/></div>
              <div className="flex items-end"><Button onClick={onAssign}>Assigner</Button></div>
              <div className="md:col-span-4 space-y-1">
                {assignments.map(a => (
                  <div key={a.id} className="flex items-center justify-between text-sm border rounded p-2">
                    <span className="font-mono text-xs">{a.user_id.slice(0,8)}… · {a.role} · zone {a.assigned_zone_id?.slice(0,8) ?? "—"}</span>
                    <Badge variant="outline">{a.status}</Badge>
                    <div className="flex gap-1">
                      <Button size="sm" variant="outline" onClick={async()=>{await updateAssignmentStatus(a.id,"paused"); loadDetail(selected);}}>Pause</Button>
                      <Button size="sm" variant="outline" onClick={async()=>{await updateAssignmentStatus(a.id,"removed"); loadDetail(selected);}}>Retirer</Button>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>Visites ({visits.length})</CardTitle></CardHeader>
            <CardContent className="space-y-2 max-h-[500px] overflow-auto">
              {visits.length === 0 && <p className="text-sm text-muted-foreground">Aucune visite.</p>}
              {visits.map(v => (
                <div key={v.id} className="border rounded p-2 text-sm flex flex-wrap gap-2 justify-between items-center">
                  <div>
                    <div className="font-medium">{v.merchant_name}</div>
                    <div className="text-xs text-muted-foreground">
                      {v.merchant_phone ?? "—"} · {v.merchant_category ?? "—"} · {v.address_text ?? "—"}
                      {v.lat && ` · ${v.lat.toFixed(4)}, ${v.lng.toFixed(4)}`}
                    </div>
                  </div>
                  <Badge variant="secondary">{INTEREST_LABEL[v.interest_level as keyof typeof INTEREST_LABEL]}</Badge>
                  <Badge>{VISIT_STATUS_LABEL[v.visit_status as keyof typeof VISIT_STATUS_LABEL]}</Badge>
                </div>
              ))}
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>Rapports quotidiens ({reports.length})</CardTitle></CardHeader>
            <CardContent className="space-y-2 max-h-[500px] overflow-auto">
              {reports.length === 0 && <p className="text-sm text-muted-foreground">Aucun rapport.</p>}
              {reports.map(r => (
                <div key={r.id} className="border rounded p-2 text-sm flex flex-wrap gap-2 justify-between items-center">
                  <div>
                    <div className="font-medium">{r.report_date} · agent {r.user_id.slice(0,8)}…</div>
                    <div className="text-xs text-muted-foreground">
                      visités {r.merchants_visited_count} · soumis {r.merchants_submitted_count} ·
                      intéressés {r.merchants_interested_count} · convertis {r.merchants_converted_count}
                      {" · transport matin "}{r.transport_morning_paid?"✓":"✗"}
                      {" · retour "}{r.transport_return_paid?"✓":"✗"}
                    </div>
                    {r.notes && <div className="text-xs italic mt-1">{r.notes}</div>}
                  </div>
                  <Badge>{REPORT_STATUS_LABEL[r.status as keyof typeof REPORT_STATUS_LABEL]}</Badge>
                  <div className="flex gap-1">
                    <Button size="sm" variant="outline" onClick={async()=>{await setReportStatus(r.id,"reviewed",me!); loadDetail(selected);}}>Examiné</Button>
                    <Button size="sm" variant="outline" onClick={async()=>{await setReportStatus(r.id,"needs_correction",me!); loadDetail(selected);}}>À corriger</Button>
                    <Button size="sm" onClick={async()=>{await setReportStatus(r.id,"approved",me!); loadDetail(selected);}}>Approuver</Button>
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="border rounded p-3">
      <div className="text-2xl font-semibold">{value}</div>
      <div className="text-xs text-muted-foreground">{label}</div>
    </div>
  );
}