import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import {
  listMyAssignments, listVisits, listReports, setReportStatus,
  VISIT_STATUS_LABEL, REPORT_STATUS_LABEL, INTEREST_LABEL,
} from "@/lib/maps/field";

export default function FieldCaptain() {
  const [assignments, setAssignments] = useState<any[]>([]);
  const [visits, setVisits] = useState<any[]>([]);
  const [reports, setReports] = useState<any[]>([]);
  const [pilotId, setPilotId] = useState<string | null>(null);
  const [me, setMe] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setMe(data.user?.id ?? null));
    (async () => {
      try {
        const a = await listMyAssignments();
        const captain = a.find((x: any) => x.role === "field_captain");
        setAssignments(a);
        if (captain) setPilotId(captain.pilot_id);
      } catch (e: any) { toast.error(e.message); }
    })();
  }, []);

  useEffect(() => { if (pilotId) load(); }, [pilotId]);
  async function load() {
    if (!pilotId) return;
    try {
      const [v, r] = await Promise.all([listVisits(pilotId), listReports(pilotId)]);
      setVisits(v); setReports(r);
    } catch (e: any) { toast.error(e.message); }
  }

  if (!assignments.length) {
    return <div className="p-6 text-sm text-muted-foreground">Aucune affectation active.</div>;
  }

  const today = new Date().toISOString().slice(0, 10);
  const todayVisits = visits.filter(v => v.created_at?.slice(0,10) === today);
  const todayReports = reports.filter(r => r.report_date === today);

  return (
    <div className="space-y-4 p-4 max-w-3xl mx-auto">
      <h1 className="text-xl font-semibold">Espace Captain terrain</h1>
      <Card>
        <CardHeader><CardTitle>Mes affectations</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm">
          {assignments.map(a => (
            <div key={a.id} className="border rounded p-2 flex justify-between items-center">
              <span>{a.field_pilots?.name ?? a.pilot_id.slice(0,8)} · <b>{a.role}</b></span>
              <Badge>{a.status}</Badge>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Visites aujourd'hui ({todayVisits.length})</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm max-h-[400px] overflow-auto">
          {todayVisits.length === 0 && <p className="text-muted-foreground">Aucune visite aujourd'hui.</p>}
          {todayVisits.map(v => (
            <div key={v.id} className="border rounded p-2 flex flex-wrap gap-2 justify-between">
              <div>
                <div className="font-medium">{v.merchant_name}</div>
                <div className="text-xs text-muted-foreground">{v.merchant_phone ?? "—"} · {v.address_text ?? "—"}</div>
              </div>
              <Badge variant="secondary">{INTEREST_LABEL[v.interest_level as keyof typeof INTEREST_LABEL]}</Badge>
              <Badge>{VISIT_STATUS_LABEL[v.visit_status as keyof typeof VISIT_STATUS_LABEL]}</Badge>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Rapports à examiner ({todayReports.length})</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm max-h-[400px] overflow-auto">
          {todayReports.length === 0 && <p className="text-muted-foreground">Aucun rapport aujourd'hui.</p>}
          {todayReports.map(r => (
            <div key={r.id} className="border rounded p-2 flex flex-wrap gap-2 justify-between items-center">
              <div>
                <div className="font-medium">agent {r.user_id.slice(0,8)}…</div>
                <div className="text-xs text-muted-foreground">
                  V {r.merchants_visited_count} · S {r.merchants_submitted_count} ·
                  I {r.merchants_interested_count} · C {r.merchants_converted_count}
                </div>
              </div>
              <Badge>{REPORT_STATUS_LABEL[r.status as keyof typeof REPORT_STATUS_LABEL]}</Badge>
              <div className="flex gap-1">
                <Button size="sm" variant="outline" onClick={async()=>{await setReportStatus(r.id,"reviewed",me!); load();}}>Examiné</Button>
                <Button size="sm" variant="outline" onClick={async()=>{await setReportStatus(r.id,"needs_correction",me!); load();}}>À corriger</Button>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}