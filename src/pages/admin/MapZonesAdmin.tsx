import { useEffect, useMemo, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/hooks/use-toast";
import {
  listServiceZones, upsertServiceZone, updateServiceZoneVerification,
  parseBoundaryGeoJSON, VERIFICATION_LABEL, ZONE_SERVICE_KEYS,
  type MapVerificationStatus, type ZonePriority, type ZoneStatus,
} from "@/lib/maps/canonical";
import { Loader2, Plus, ShieldCheck } from "lucide-react";

const STATUSES: ZoneStatus[] = ["pilot","active","paused","inactive","needs_review"];
const PRIORITIES: ZonePriority[] = ["low","normal","high","critical"];
const VERIFICATIONS: MapVerificationStatus[] = [
  "unverified","submitted","field_checked","admin_verified","trusted","needs_review","duplicate","closed",
];

function statusTone(s: string) {
  if (s === "active" || s === "trusted") return "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400";
  if (s === "pilot") return "bg-blue-500/15 text-blue-700 dark:text-blue-400";
  if (s === "paused") return "bg-amber-500/15 text-amber-700 dark:text-amber-500";
  if (s === "needs_review") return "bg-orange-500/15 text-orange-700 dark:text-orange-400";
  return "bg-muted text-muted-foreground";
}

const blankZone = {
  name: "", commune: "", district: "",
  center_lat: "", center_lng: "", radius_meters: "1000",
  boundary_geojson: "",
  status: "pilot" as ZoneStatus,
  priority: "normal" as ZonePriority,
  services_enabled: { moto: true, repas: false, marche: false, envoyer: false, agents: false },
  ops_notes: "", driver_notes: "", merchant_notes: "", coverage_notes: "",
};

export default function MapZonesAdmin() {
  const [zones, setZones] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<any | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [filterVerif, setFilterVerif] = useState<string>("all");
  const [filterService, setFilterService] = useState<string>("all");

  async function refresh() {
    setLoading(true);
    try { setZones(await listServiceZones()); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
    finally { setLoading(false); }
  }
  useEffect(() => { refresh(); }, []);

  const filtered = useMemo(() => zones.filter((z) => {
    if (filterStatus !== "all" && z.status !== filterStatus) return false;
    if (filterVerif !== "all" && z.verification_status !== filterVerif) return false;
    if (filterService !== "all" && !z.services_enabled?.[filterService]) return false;
    return true;
  }), [zones, filterStatus, filterVerif, filterService]);

  async function save() {
    if (!editing) return;
    const geo = parseBoundaryGeoJSON(editing.boundary_geojson);
    if (!geo.ok) { toast({ title: "GeoJSON invalide", description: (geo as { ok: false; error: string }).error, variant: "destructive" }); return; }
    try {
      await upsertServiceZone({
        ...(editing.id ? { id: editing.id } : {}),
        name: editing.name,
        commune: editing.commune || null,
        district: editing.district || null,
        center_lat: editing.center_lat ? Number(editing.center_lat) : null,
        center_lng: editing.center_lng ? Number(editing.center_lng) : null,
        radius_meters: editing.radius_meters ? Number(editing.radius_meters) : null,
        boundary_geojson: geo.value,
        status: editing.status,
        priority: editing.priority,
        services_enabled: editing.services_enabled,
        ops_notes: editing.ops_notes || null,
        driver_notes: editing.driver_notes || null,
        merchant_notes: editing.merchant_notes || null,
        coverage_notes: editing.coverage_notes || null,
      });
      toast({ title: "Zone enregistrée" });
      setEditing(null);
      refresh();
    } catch (e: any) {
      toast({ title: "Erreur", description: e.message, variant: "destructive" });
    }
  }

  async function setVerif(id: string, v: MapVerificationStatus) {
    try { await updateServiceZoneVerification(id, v); toast({ title: "Vérification mise à jour" }); refresh(); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
  }

  return (
    <ModulePage module="zones" title="Carte — Zones de service" subtitle="map_service_zones · couverture opérationnelle, services, vérification" actions={
      <Button size="sm" onClick={() => setEditing({ ...blankZone })}><Plus className="w-4 h-4 mr-1" /> Nouvelle zone</Button>
    }>
      <div className="flex flex-wrap gap-2 items-center">
        <Select value={filterStatus} onValueChange={setFilterStatus}>
          <SelectTrigger className="w-[160px] h-8 text-xs"><SelectValue placeholder="Statut" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tous statuts</SelectItem>
            {STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={filterVerif} onValueChange={setFilterVerif}>
          <SelectTrigger className="w-[180px] h-8 text-xs"><SelectValue placeholder="Vérification" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Toutes vérifications</SelectItem>
            {VERIFICATIONS.map((v) => <SelectItem key={v} value={v}>{VERIFICATION_LABEL[v]}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={filterService} onValueChange={setFilterService}>
          <SelectTrigger className="w-[150px] h-8 text-xs"><SelectValue placeholder="Service" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tous services</SelectItem>
            {ZONE_SERVICE_KEYS.map((k) => <SelectItem key={k} value={k}>{k}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      {loading ? (
        <Card className="p-6 text-center text-sm text-muted-foreground"><Loader2 className="w-4 h-4 inline animate-spin mr-2" /> Chargement…</Card>
      ) : filtered.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">
          Aucune zone de service. Créez-en une pour démarrer.
        </Card>
      ) : (
        <div className="grid gap-2 md:grid-cols-2">
          {filtered.map((z) => (
            <Card key={z.id} className="p-3 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-semibold text-sm truncate">{z.name}</p>
                  <p className="text-[11px] text-muted-foreground truncate">{[z.commune, z.district].filter(Boolean).join(" · ") || "—"}</p>
                </div>
                <Button variant="ghost" size="sm" onClick={() => setEditing({
                  ...z,
                  center_lat: z.center_lat ?? "", center_lng: z.center_lng ?? "",
                  radius_meters: z.radius_meters ?? "",
                  boundary_geojson: z.boundary_geojson ? JSON.stringify(z.boundary_geojson, null, 2) : "",
                  services_enabled: z.services_enabled ?? {},
                })}>Éditer</Button>
              </div>
              <div className="flex flex-wrap gap-1">
                <Badge variant="outline" className={`text-[10px] ${statusTone(z.status)}`}>{z.status}</Badge>
                <Badge variant="outline" className="text-[10px]">{z.priority}</Badge>
                <Badge variant="outline" className={`text-[10px] ${statusTone(z.verification_status)}`}>
                  <ShieldCheck className="w-3 h-3 mr-1" />{VERIFICATION_LABEL[z.verification_status as MapVerificationStatus]}
                </Badge>
                <Badge variant="outline" className="text-[10px]">Confiance {z.confidence_score}%</Badge>
              </div>
              <div className="flex flex-wrap gap-1">
                {ZONE_SERVICE_KEYS.filter((k) => z.services_enabled?.[k]).map((k) => (
                  <Badge key={k} className="text-[10px] bg-primary/10 text-primary">{k}</Badge>
                ))}
              </div>
              <div className="flex flex-wrap gap-1 pt-1">
                {(["field_checked","admin_verified","trusted","needs_review"] as MapVerificationStatus[]).map((v) => (
                  <Button key={v} size="sm" variant="outline" className="h-7 text-[11px]" onClick={() => setVerif(z.id, v)}>
                    {VERIFICATION_LABEL[v]}
                  </Button>
                ))}
              </div>
            </Card>
          ))}
        </div>
      )}

      {editing && (
        <Card className="p-4 space-y-4 mt-4 border-primary/40">
          <div className="flex items-center justify-between">
            <p className="font-semibold text-sm">{editing.id ? "Éditer la zone" : "Nouvelle zone"}</p>
            <Button variant="ghost" size="sm" onClick={() => setEditing(null)}>Annuler</Button>
          </div>

          <section className="space-y-2">
            <p className="admin-eyebrow">Identité</p>
            <div className="grid md:grid-cols-3 gap-2">
              <div><Label className="text-xs">Nom</Label><Input value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} /></div>
              <div><Label className="text-xs">Commune</Label><Input value={editing.commune} onChange={(e) => setEditing({ ...editing, commune: e.target.value })} /></div>
              <div><Label className="text-xs">District</Label><Input value={editing.district} onChange={(e) => setEditing({ ...editing, district: e.target.value })} /></div>
            </div>
          </section>

          <section className="space-y-2">
            <p className="admin-eyebrow">Couverture</p>
            <div className="grid md:grid-cols-3 gap-2">
              <div><Label className="text-xs">Centre lat</Label><Input value={editing.center_lat} onChange={(e) => setEditing({ ...editing, center_lat: e.target.value })} placeholder="9.5092" /></div>
              <div><Label className="text-xs">Centre lng</Label><Input value={editing.center_lng} onChange={(e) => setEditing({ ...editing, center_lng: e.target.value })} placeholder="-13.7122" /></div>
              <div><Label className="text-xs">Rayon (m)</Label><Input value={editing.radius_meters} onChange={(e) => setEditing({ ...editing, radius_meters: e.target.value })} placeholder="1000" /></div>
            </div>
            <div>
              <Label className="text-xs">Boundary GeoJSON (optionnel)</Label>
              <Textarea rows={4} value={editing.boundary_geojson} onChange={(e) => setEditing({ ...editing, boundary_geojson: e.target.value })} placeholder='{"type":"Polygon","coordinates":[[[…]]]}' />
              <p className="text-[10px] text-muted-foreground mt-1">Si invalide, le rendu retombe sur cercle (centre + rayon).</p>
            </div>
          </section>

          <section className="space-y-2">
            <p className="admin-eyebrow">Services</p>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
              {ZONE_SERVICE_KEYS.map((k) => (
                <label key={k} className="flex items-center gap-2 text-xs border rounded-md px-2 py-1.5">
                  <Switch checked={!!editing.services_enabled?.[k]} onCheckedChange={(v) => setEditing({ ...editing, services_enabled: { ...editing.services_enabled, [k]: v } })} />
                  {k}
                </label>
              ))}
            </div>
          </section>

          <section className="space-y-2">
            <p className="admin-eyebrow">Vérification</p>
            <div className="grid md:grid-cols-3 gap-2">
              <div>
                <Label className="text-xs">Statut</Label>
                <Select value={editing.status} onValueChange={(v) => setEditing({ ...editing, status: v })}>
                  <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                  <SelectContent>{STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div>
                <Label className="text-xs">Priorité</Label>
                <Select value={editing.priority} onValueChange={(v) => setEditing({ ...editing, priority: v })}>
                  <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                  <SelectContent>{PRIORITIES.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
          </section>

          <section className="space-y-2">
            <p className="admin-eyebrow">Notes</p>
            <div className="grid md:grid-cols-2 gap-2">
              <Textarea rows={2} placeholder="Ops" value={editing.ops_notes} onChange={(e) => setEditing({ ...editing, ops_notes: e.target.value })} />
              <Textarea rows={2} placeholder="Chauffeurs" value={editing.driver_notes} onChange={(e) => setEditing({ ...editing, driver_notes: e.target.value })} />
              <Textarea rows={2} placeholder="Marchands" value={editing.merchant_notes} onChange={(e) => setEditing({ ...editing, merchant_notes: e.target.value })} />
              <Textarea rows={2} placeholder="Couverture" value={editing.coverage_notes} onChange={(e) => setEditing({ ...editing, coverage_notes: e.target.value })} />
            </div>
          </section>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setEditing(null)}>Annuler</Button>
            <Button onClick={save}>Enregistrer</Button>
          </div>
        </Card>
      )}
    </ModulePage>
  );
}