import { useEffect, useMemo, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/hooks/use-toast";
import {
  listDuplicateCandidates, getPlacesByIds, detectPlaceDuplicates,
  mergeMapPlaces, markPlaceDuplicate, updateDuplicateCandidateStatus,
  DUP_STATUS_LABEL, VERIFICATION_LABEL,
  type DuplicateCandidateStatus, type MapVerificationStatus,
} from "@/lib/maps/canonical";
import { Loader2, ShieldCheck, ArrowRight, ArrowLeft, X, MapPin, RefreshCw } from "lucide-react";

const STATUSES: (DuplicateCandidateStatus | "all")[] = [
  "open", "needs_field_check", "confirmed_duplicate", "dismissed", "merged", "all",
];

function tone(s: MapVerificationStatus) {
  if (s === "trusted" || s === "admin_verified") return "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400";
  if (s === "needs_review") return "bg-orange-500/15 text-orange-700 dark:text-orange-400";
  if (s === "duplicate" || s === "closed") return "bg-muted text-muted-foreground";
  return "bg-blue-500/15 text-blue-700 dark:text-blue-400";
}

function PlaceSummary({ p }: { p: any }) {
  if (!p) return <div className="text-xs text-muted-foreground">—</div>;
  return (
    <div className="space-y-1 min-w-0">
      <p className="font-semibold text-sm truncate">{p.name}</p>
      <p className="text-[11px] text-muted-foreground truncate">
        {[p.category, p.commune, p.neighborhood].filter(Boolean).join(" · ") || "—"}
      </p>
      <p className="text-[11px] text-muted-foreground">
        {Number.isFinite(p.lat) && Number.isFinite(p.lng)
          ? `${(p.lat as number).toFixed(5)}, ${(p.lng as number).toFixed(5)}`
          : "—"}
      </p>
      <div className="flex items-center gap-2 flex-wrap">
        <Badge variant="outline" className={`text-[10px] ${tone(p.verification_status)}`}>
          <ShieldCheck className="w-3 h-3 mr-1" />
          {VERIFICATION_LABEL[p.verification_status as MapVerificationStatus]}
        </Badge>
        <span className="text-[10px] text-muted-foreground">Confiance {p.confidence_score}%</span>
        {p.duplicate_of && (
          <Badge variant="outline" className="text-[10px] bg-muted text-muted-foreground">déjà doublon</Badge>
        )}
      </div>
      {(p.landmark_note || p.pickup_note || p.entrance_note) && (
        <p className="text-[11px] text-muted-foreground line-clamp-2">
          {[p.landmark_note, p.pickup_note, p.entrance_note].filter(Boolean).join(" · ")}
        </p>
      )}
    </div>
  );
}

export default function MapDuplicatesAdmin() {
  const [filter, setFilter] = useState<DuplicateCandidateStatus | "all">("open");
  const [loading, setLoading] = useState(true);
  const [scanning, setScanning] = useState(false);
  const [rows, setRows] = useState<any[]>([]);
  const [placeMap, setPlaceMap] = useState<Record<string, any>>({});

  async function refresh() {
    setLoading(true);
    try {
      const list = await listDuplicateCandidates(filter);
      setRows(list);
      const ids = Array.from(new Set(list.flatMap((r) => [r.place_a_id, r.place_b_id])));
      if (ids.length) {
        const places = await getPlacesByIds(ids);
        const map: Record<string, any> = {};
        places.forEach((p: any) => { map[p.id] = p; });
        setPlaceMap(map);
      } else {
        setPlaceMap({});
      }
    } catch (e: any) {
      toast({ title: "Erreur", description: e.message, variant: "destructive" });
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { refresh(); /* eslint-disable-next-line */ }, [filter]);

  async function runScan() {
    setScanning(true);
    try {
      const n = await detectPlaceDuplicates();
      toast({ title: "Scan terminé", description: `${n} nouveau(x) candidat(s)` });
      refresh();
    } catch (e: any) {
      toast({ title: "Erreur scan", description: e.message, variant: "destructive" });
    } finally {
      setScanning(false);
    }
  }

  async function doMerge(row: any, targetIsA: boolean) {
    const target = targetIsA ? row.place_a_id : row.place_b_id;
    const source = targetIsA ? row.place_b_id : row.place_a_id;
    if (!confirm("Confirmer la fusion ? La source sera désactivée (non supprimée).")) return;
    try {
      const res = await mergeMapPlaces({ sourcePlaceId: source, targetPlaceId: target, candidateId: row.id });
      toast({ title: "Fusion effectuée", description: `Stores: ${res.moved_stores}, reports: ${res.moved_reports}` });
      refresh();
    } catch (e: any) {
      toast({ title: "Erreur fusion", description: e.message, variant: "destructive" });
    }
  }

  async function doMark(row: any, targetIsA: boolean) {
    const target = targetIsA ? row.place_a_id : row.place_b_id;
    const source = targetIsA ? row.place_b_id : row.place_a_id;
    try {
      await markPlaceDuplicate({ sourcePlaceId: source, targetPlaceId: target, candidateId: row.id });
      toast({ title: "Doublon marqué" });
      refresh();
    } catch (e: any) {
      toast({ title: "Erreur", description: e.message, variant: "destructive" });
    }
  }

  async function setStatus(row: any, status: DuplicateCandidateStatus) {
    try {
      await updateDuplicateCandidateStatus(row.id, status);
      toast({ title: "Candidat mis à jour" });
      refresh();
    } catch (e: any) {
      toast({ title: "Erreur", description: e.message, variant: "destructive" });
    }
  }

  const cards = useMemo(() => rows.map((r) => {
    const a = placeMap[r.place_a_id];
    const b = placeMap[r.place_b_id];
    return { r, a, b };
  }), [rows, placeMap]);

  return (
    <ModulePage
      module="zones"
      title="Carte — Doublons"
      subtitle="map_place_duplicate_candidates · revue & fusion contrôlée"
    >
      <div className="flex flex-wrap items-center gap-2">
        <Select value={filter} onValueChange={(v) => setFilter(v as any)}>
          <SelectTrigger className="w-[200px] h-8 text-xs"><SelectValue /></SelectTrigger>
          <SelectContent>
            {STATUSES.map((s) => (
              <SelectItem key={s} value={s}>
                {s === "all" ? "Tous" : DUP_STATUS_LABEL[s as DuplicateCandidateStatus]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button size="sm" variant="outline" onClick={runScan} disabled={scanning}>
          {scanning ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> : <RefreshCw className="w-3.5 h-3.5 mr-1" />}
          Lancer scan
        </Button>
        <Button size="sm" variant="ghost" onClick={refresh}>Rafraîchir</Button>
      </div>

      {loading ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">
          <Loader2 className="w-4 h-4 inline animate-spin mr-2" /> Chargement…
        </Card>
      ) : cards.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">
          Aucun candidat doublon.
        </Card>
      ) : (
        <div className="grid gap-3">
          {cards.map(({ r, a, b }) => (
            <Card key={r.id} className="p-3 space-y-3">
              <div className="flex items-center justify-between gap-2 flex-wrap">
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge variant="outline" className="text-[10px] bg-primary/10 text-primary">
                    Score {r.score}
                  </Badge>
                  {Number.isFinite(r.distance_meters) && (
                    <Badge variant="outline" className="text-[10px]">
                      <MapPin className="w-3 h-3 mr-1" />
                      {Math.round(r.distance_meters)} m
                    </Badge>
                  )}
                  {(r.reason_codes ?? []).map((rc: string) => (
                    <Badge key={rc} variant="outline" className="text-[10px] bg-muted">{rc}</Badge>
                  ))}
                </div>
                <Badge variant="outline" className="text-[10px]">
                  {DUP_STATUS_LABEL[r.status as DuplicateCandidateStatus] ?? r.status}
                </Badge>
              </div>

              <div className="grid md:grid-cols-2 gap-3">
                <div className="rounded-md border p-2"><PlaceSummary p={a} /></div>
                <div className="rounded-md border p-2"><PlaceSummary p={b} /></div>
              </div>

              {r.status === "open" || r.status === "needs_field_check" ? (
                <div className="flex flex-wrap gap-1 pt-1">
                  <Button size="sm" variant="outline" className="h-7 text-[11px]"
                          onClick={() => doMerge(r, true)} disabled={!a || !b}>
                    <ArrowLeft className="w-3 h-3 mr-1" /> Fusionner B → A
                  </Button>
                  <Button size="sm" variant="outline" className="h-7 text-[11px]"
                          onClick={() => doMerge(r, false)} disabled={!a || !b}>
                    Fusionner A → B <ArrowRight className="w-3 h-3 ml-1" />
                  </Button>
                  <Button size="sm" variant="outline" className="h-7 text-[11px]"
                          onClick={() => doMark(r, true)} disabled={!a || !b}>
                    Marquer B doublon de A
                  </Button>
                  <Button size="sm" variant="outline" className="h-7 text-[11px]"
                          onClick={() => doMark(r, false)} disabled={!a || !b}>
                    Marquer A doublon de B
                  </Button>
                  <Button size="sm" variant="outline" className="h-7 text-[11px]"
                          onClick={() => setStatus(r, "needs_field_check")}>
                    Vérif terrain
                  </Button>
                  <Button size="sm" variant="ghost" className="h-7 text-[11px]"
                          onClick={() => setStatus(r, "dismissed")}>
                    <X className="w-3 h-3 mr-1" /> Rejeter
                  </Button>
                </div>
              ) : (
                <div className="text-[11px] text-muted-foreground">
                  Revu le {r.reviewed_at ? new Date(r.reviewed_at).toLocaleString("fr-FR") : "—"}
                  {r.notes ? ` · ${r.notes}` : ""}
                </div>
              )}
            </Card>
          ))}
        </div>
      )}
    </ModulePage>
  );
}