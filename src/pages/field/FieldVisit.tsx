import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import {
  listMyAssignments, submitVisit, submitDailyReport,
  type FieldVisitInterest,
} from "@/lib/maps/field";
import {
  listPendingDrafts, saveDraft, markSubmitted, markFailed, removeDraft,
  type FieldVisitDraft,
} from "@/lib/maps/fieldDrafts";

const INTERESTS: { value: FieldVisitInterest; label: string }[] = [
  { value: "cold", label: "Froid" },
  { value: "interested", label: "Intéressé" },
  { value: "signed_up", label: "Inscrit" },
  { value: "needs_follow_up", label: "À relancer" },
  { value: "rejected", label: "Refusé" },
];

export default function FieldVisit() {
  const [assignments, setAssignments] = useState<any[]>([]);
  const [pilotId, setPilotId] = useState("");
  const [zoneId, setZoneId] = useState("");
  const [form, setForm] = useState({
    merchantName: "", phone: "", category: "",
    interest: "cold" as FieldVisitInterest,
    lat: "" as string, lng: "" as string,
    addressText: "", landmark: "", entrance: "", pickup: "", notes: "",
  });
  const [busy, setBusy] = useState(false);
  const [drafts, setDrafts] = useState<FieldVisitDraft[]>([]);

  function refreshDrafts() { setDrafts(listPendingDrafts()); }

  const [report, setReport] = useState({
    visited: 0, submitted: 0, interested: 0, converted: 0,
    morning: false, ret: false, notes: "",
  });

  useEffect(() => {
    listMyAssignments().then((a) => {
      setAssignments(a);
      if (a[0]) {
        setPilotId(a[0].pilot_id);
        if (a[0].assigned_zone_id) setZoneId(a[0].assigned_zone_id);
      }
    }).catch(e => toast.error(e.message));
    refreshDrafts();
  }, []);

  function useCurrentLocation() {
    if (!navigator.geolocation) return toast.error("Géoloc indisponible");
    navigator.geolocation.getCurrentPosition(
      (pos) => setForm(f => ({ ...f, lat: pos.coords.latitude.toFixed(6), lng: pos.coords.longitude.toFixed(6) })),
      () => toast.error("Position refusée"),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  async function onSubmit() {
    if (!pilotId) return toast.error("Pilote requis");
    if (!form.merchantName.trim()) return toast.error("Nom marchand requis");
    setBusy(true);
    const lat = form.lat ? Number(form.lat) : null;
    const lng = form.lng ? Number(form.lng) : null;
    const visitPayload = {
      pilotId,
      merchantName: form.merchantName.trim(),
      phone: form.phone || undefined,
      category: form.category || undefined,
      interest: form.interest,
      lat, lng,
      addressText: form.addressText || undefined,
      landmark: form.landmark || undefined,
      entrance: form.entrance || undefined,
      pickup: form.pickup || undefined,
      notes: form.notes || undefined,
      zoneId: zoneId || null,
    };
    // Offline guard — save locally instead of attempting submission.
    if (typeof navigator !== "undefined" && navigator.onLine === false) {
      saveDraft({ pilotId, payload: visitPayload as any, status: "draft" });
      toast.message("Brouillon sauvegardé sur cet appareil");
      refreshDrafts();
      setBusy(false);
      return;
    }
    try {
      await submitVisit(visitPayload as any);
      toast.success("Visite enregistrée");
      setForm({
        merchantName: "", phone: "", category: "", interest: "cold",
        lat: "", lng: "", addressText: "", landmark: "", entrance: "", pickup: "", notes: "",
      });
    } catch (e: any) {
      // Network/transient — save as pending retry instead of losing the work.
      const draft = saveDraft({ pilotId, payload: visitPayload as any, status: "pending_retry", lastError: e?.message ?? "Erreur réseau" });
      toast.message("Brouillon sauvegardé — réessayez quand vous serez connecté");
      refreshDrafts();
      void draft;
    }
    finally { setBusy(false); }
  }

  async function retryDraft(draft: FieldVisitDraft) {
    if (typeof navigator !== "undefined" && navigator.onLine === false) {
      return toast.error("Toujours hors-ligne");
    }
    try {
      await submitVisit(draft.payload as any);
      markSubmitted(draft.id);
      toast.success("Visite envoyée");
      refreshDrafts();
    } catch (e: any) {
      markFailed(draft.id, e?.message ?? "Échec");
      refreshDrafts();
      toast.error(e?.message ?? "Échec de l'envoi");
    }
  }

  async function onSubmitReport() {
    if (!pilotId) return toast.error("Pilote requis");
    try {
      await submitDailyReport({
        pilot_id: pilotId, zone_id: zoneId || null,
        merchants_visited_count: Number(report.visited) || 0,
        merchants_submitted_count: Number(report.submitted) || 0,
        merchants_interested_count: Number(report.interested) || 0,
        merchants_converted_count: Number(report.converted) || 0,
        transport_morning_paid: report.morning,
        transport_return_paid: report.ret,
        notes: report.notes || null,
      });
      toast.success("Rapport soumis");
    } catch (e: any) { toast.error(e.message); }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-xl font-semibold">Nouvelle visite marchand</h1>

      {assignments.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucune affectation active. Contactez votre captain.</p>
      ) : (
        <>
          {drafts.length > 0 && (
            <Card>
              <CardHeader><CardTitle>Brouillons hors-ligne</CardTitle></CardHeader>
              <CardContent className="space-y-2">
                <p className="text-xs text-muted-foreground">
                  Sauvegardés sur cet appareil. Médias non pris en charge hors-ligne pour l'instant.
                </p>
                {drafts.map((d) => (
                  <div key={d.id} className="flex items-center justify-between gap-2 rounded border border-border/60 p-2 text-sm">
                    <div className="min-w-0">
                      <div className="font-medium truncate">{(d.payload as any)?.merchantName ?? "Visite"}</div>
                      <div className="text-[11px] text-muted-foreground">
                        {d.status === "pending_retry" ? "À renvoyer" : d.status === "failed" ? `Échec — ${d.lastError ?? ""}` : "Brouillon"}
                      </div>
                    </div>
                    <div className="flex gap-1">
                      <Button size="sm" variant="outline" onClick={() => retryDraft(d)}>Renvoyer</Button>
                      <Button size="sm" variant="ghost" onClick={() => { removeDraft(d.id); refreshDrafts(); }}>Supprimer</Button>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
          <Card>
            <CardHeader><CardTitle>Visite</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              <div>
                <Label>Pilote</Label>
                <select className="w-full border rounded h-10 px-2" value={pilotId} onChange={e=>setPilotId(e.target.value)}>
                  {assignments.map(a => (
                    <option key={a.pilot_id} value={a.pilot_id}>{a.field_pilots?.name ?? a.pilot_id.slice(0,8)}</option>
                  ))}
                </select>
              </div>
              <div><Label>Nom marchand *</Label><Input value={form.merchantName} onChange={e=>setForm({...form,merchantName:e.target.value})}/></div>
              <div><Label>Téléphone</Label><Input value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></div>
              <div><Label>Catégorie</Label><Input value={form.category} onChange={e=>setForm({...form,category:e.target.value})}/></div>
              <div>
                <Label>Intérêt</Label>
                <select className="w-full border rounded h-10 px-2" value={form.interest} onChange={e=>setForm({...form,interest:e.target.value as FieldVisitInterest})}>
                  {INTERESTS.map(i => <option key={i.value} value={i.value}>{i.label}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div><Label>Lat</Label><Input value={form.lat} onChange={e=>setForm({...form,lat:e.target.value})}/></div>
                <div><Label>Lng</Label><Input value={form.lng} onChange={e=>setForm({...form,lng:e.target.value})}/></div>
              </div>
              <Button variant="outline" className="w-full" onClick={useCurrentLocation}>📍 Utiliser ma position</Button>
              <div><Label>Adresse</Label><Input value={form.addressText} onChange={e=>setForm({...form,addressText:e.target.value})}/></div>
              <div><Label>Point de repère</Label><Input value={form.landmark} onChange={e=>setForm({...form,landmark:e.target.value})}/></div>
              <div><Label>Notes</Label><Textarea value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></div>
              <Button onClick={onSubmit} disabled={busy} className="w-full">{busy?"Envoi…":"Enregistrer visite"}</Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>Rapport journalier</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <div><Label>Visités</Label><Input type="number" value={report.visited} onChange={e=>setReport({...report,visited:Number(e.target.value)})}/></div>
                <div><Label>Soumis</Label><Input type="number" value={report.submitted} onChange={e=>setReport({...report,submitted:Number(e.target.value)})}/></div>
                <div><Label>Intéressés</Label><Input type="number" value={report.interested} onChange={e=>setReport({...report,interested:Number(e.target.value)})}/></div>
                <div><Label>Convertis</Label><Input type="number" value={report.converted} onChange={e=>setReport({...report,converted:Number(e.target.value)})}/></div>
              </div>
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={report.morning} onChange={e=>setReport({...report,morning:e.target.checked})}/> Transport matin reçu</label>
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={report.ret} onChange={e=>setReport({...report,ret:e.target.checked})}/> Transport retour reçu</label>
              <div className="text-xs text-muted-foreground">Prime de performance traitée séparément.</div>
              <div><Label>Notes</Label><Textarea value={report.notes} onChange={e=>setReport({...report,notes:e.target.value})}/></div>
              <Button onClick={onSubmitReport} className="w-full">Soumettre rapport du jour</Button>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}