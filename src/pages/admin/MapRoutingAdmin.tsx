import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import {
  getRouteEstimate, fallbackEstimate, compareRouteToObservedTroncons,
  listRouteObservations, updateRouteObservationStatus,
  type RouteEstimate, type RouteMode,
} from "@/lib/maps/routing";

export default function MapRoutingAdmin() {
  const [oLat, setOLat] = useState("9.5370");
  const [oLng, setOLng] = useState("-13.6785");
  const [dLat, setDLat] = useState("9.6412");
  const [dLng, setDLng] = useState("-13.5784");
  const [mode, setMode] = useState<RouteMode>("moto");
  const [provResult, setProvResult] = useState<RouteEstimate | null>(null);
  const [fbResult, setFbResult] = useState<RouteEstimate | null>(null);
  const [troncon, setTroncon] = useState<any>(null);
  const [tDep, setTDep] = useState("Madina");
  const [tDest, setTDest] = useState("Kaloum");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [obs, setObs] = useState<any[]>([]);

  async function refreshObs() {
    try { setObs(await listRouteObservations(50)); } catch {/* noop */}
  }
  useEffect(() => { refreshObs(); }, []);

  async function runTest() {
    setBusy(true); setErr(null); setProvResult(null); setFbResult(null);
    try {
      const origin = { lat: parseFloat(oLat), lng: parseFloat(oLng) };
      const destination = { lat: parseFloat(dLat), lng: parseFloat(dLng) };
      const [prov] = await Promise.all([
        getRouteEstimate({ origin, destination, mode, bypassCache: true }),
      ]);
      setProvResult(prov);
      setFbResult(fallbackEstimate(origin, destination, mode));
    } catch (e) {
      setErr((e as Error)?.message ?? "Erreur");
    } finally { setBusy(false); }
  }

  async function runTronconTest() {
    setTroncon(null);
    const r = await compareRouteToObservedTroncons({
      originName: tDep, destinationName: tDest, timeOfDay: "day",
    });
    setTroncon(r ?? { _empty: true });
  }

  return (
    <div className="space-y-6 p-4">
      <header>
        <h1 className="text-2xl font-semibold">Diagnostics routage & ETA</h1>
        <p className="text-sm text-muted-foreground">
          Outil interne. Les estimations ne sont pas des tarifs officiels.
        </p>
      </header>

      <Card>
        <CardHeader><CardTitle>Test d'estimation</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
            <div><Label>Origine lat</Label><Input value={oLat} onChange={e => setOLat(e.target.value)} /></div>
            <div><Label>Origine lng</Label><Input value={oLng} onChange={e => setOLng(e.target.value)} /></div>
            <div><Label>Destination lat</Label><Input value={dLat} onChange={e => setDLat(e.target.value)} /></div>
            <div><Label>Destination lng</Label><Input value={dLng} onChange={e => setDLng(e.target.value)} /></div>
            <div>
              <Label>Mode</Label>
              <Select value={mode} onValueChange={(v) => setMode(v as RouteMode)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="moto">Moto</SelectItem>
                  <SelectItem value="car">Voiture</SelectItem>
                  <SelectItem value="walking">Marche</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <Button onClick={runTest} disabled={busy}>{busy ? "Calcul…" : "Tester"}</Button>
          {err && <p className="text-sm text-destructive">{err}</p>}

          {(provResult || fbResult) && (
            <div className="grid md:grid-cols-2 gap-3 pt-3">
              <ResultBlock title="Résultat fournisseur" r={provResult} />
              <ResultBlock title="Fallback haversine" r={fbResult} />
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Test tronçon (interne)</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div><Label>Départ</Label><Input value={tDep} onChange={e => setTDep(e.target.value)} /></div>
            <div><Label>Destination</Label><Input value={tDest} onChange={e => setTDest(e.target.value)} /></div>
            <div className="flex items-end"><Button onClick={runTronconTest} variant="secondary">Comparer</Button></div>
          </div>
          {troncon && troncon._empty && (
            <p className="text-sm text-muted-foreground">Aucun tronçon observé correspondant.</p>
          )}
          {troncon && !troncon._empty && (
            <div className="rounded-md border p-3 text-sm space-y-1">
              <div>Prix observé jour: <strong>{troncon.price_gnf?.toLocaleString("fr-FR")} GNF</strong></div>
              <div className="text-xs text-muted-foreground">{troncon.label}</div>
              <Badge variant="outline">{troncon.verification_status}</Badge>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Observations de trajet ({obs.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {obs.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucune observation enregistrée.</p>
          ) : (
            <div className="space-y-2">
              {obs.map(o => (
                <div key={o.id} className="rounded-md border p-3 text-sm flex flex-wrap items-center gap-3 justify-between">
                  <div className="space-y-0.5">
                    <div className="font-medium">
                      {o.source_module} {o.fallback_used && <Badge variant="secondary">fallback</Badge>}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {o.origin_lat?.toFixed(4)},{o.origin_lng?.toFixed(4)} → {o.destination_lat?.toFixed(4)},{o.destination_lng?.toFixed(4)}
                    </div>
                    <div className="text-xs">
                      {o.observed_distance_meters ?? "—"} m · {o.observed_duration_seconds ?? "—"} s · {o.provider_used ?? "—"}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge>{o.status}</Badge>
                    <Badge variant="outline">{o.verification_status}</Badge>
                    <Button size="sm" variant="ghost" onClick={async () => {
                      await updateRouteObservationStatus(o.id, { status: "reviewed" });
                      refreshObs();
                    }}>Marquer revue</Button>
                    <Button size="sm" variant="ghost" onClick={async () => {
                      await updateRouteObservationStatus(o.id, { verification_status: "trusted", status: "promoted" });
                      refreshObs();
                    }}>Confiance</Button>
                    <Button size="sm" variant="ghost" onClick={async () => {
                      await updateRouteObservationStatus(o.id, { status: "rejected" });
                      refreshObs();
                    }}>Rejeter</Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function ResultBlock({ title, r }: { title: string; r: RouteEstimate | null }) {
  if (!r) return null;
  return (
    <div className="rounded-md border p-3 text-sm space-y-1">
      <div className="font-medium">{title}</div>
      <div>Distance: <strong>{(r.distance_meters / 1000).toFixed(2)} km</strong></div>
      <div>Durée: <strong>{Math.round(r.duration_seconds / 60)} min</strong></div>
      <div className="flex flex-wrap gap-1.5">
        <Badge>{r.provider}</Badge>
        <Badge variant="outline">{r.confidence}</Badge>
        {r.fallback_used && <Badge variant="secondary">fallback</Badge>}
        <Badge variant="outline">polyline: {r.polyline_geojson ? "oui" : "non"}</Badge>
      </div>
      {r.warning && <p className="text-xs text-amber-600">{r.warning}</p>}
    </div>
  );
}