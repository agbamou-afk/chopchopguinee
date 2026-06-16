import { useEffect, useMemo, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/hooks/use-toast";
import { listFareTroncons, updateFareTroncon, VERIFICATION_LABEL, type MapVerificationStatus } from "@/lib/maps/canonical";
import { Loader2, ShieldCheck, MapPinOff } from "lucide-react";

const VERIFICATIONS: MapVerificationStatus[] = [
  "submitted","field_checked","admin_verified","trusted","needs_review",
];

const fmt = (n: number | null) => (n ?? 0).toLocaleString("fr-FR") + " GNF";

export default function MapTariffsAdmin() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState("");
  const [filterVerif, setFilterVerif] = useState<string>("all");
  const [onlyUnmatched, setOnlyUnmatched] = useState(false);

  async function refresh() {
    setLoading(true);
    try { setRows(await listFareTroncons()); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
    finally { setLoading(false); }
  }
  useEffect(() => { refresh(); }, []);

  const filtered = useMemo(() => rows.filter((r) => {
    if (filterVerif !== "all" && r.verification_status !== filterVerif) return false;
    if (onlyUnmatched && (r.departure_place_id || r.destination_place_id)) return false;
    if (q) {
      const s = q.toLowerCase();
      const hay = `${r.departure_name} ${r.destination_name}`.toLowerCase();
      if (!hay.includes(s)) return false;
    }
    return true;
  }), [rows, q, filterVerif, onlyUnmatched]);

  async function patch(id: string, p: any) {
    try { await updateFareTroncon(id, p); refresh(); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
  }

  return (
    <ModulePage
      module="zones"
      title="Carte — Tarifs moto (tronçons)"
      subtitle="map_fare_troncons · réf. interne, non publié comme prix CHOP officiel"
    >
      <Card className="p-3 bg-amber-500/10 border-amber-500/30 text-[12px]">
        Référence terrain uniquement. À ne pas exposer comme tarif client officiel à ce stade.
      </Card>

      <div className="flex flex-wrap gap-2 items-center">
        <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Recherche tronçon…" className="w-56 h-8 text-xs" />
        <Select value={filterVerif} onValueChange={setFilterVerif}>
          <SelectTrigger className="w-[180px] h-8 text-xs"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Toutes vérifications</SelectItem>
            {VERIFICATIONS.map((v) => <SelectItem key={v} value={v}>{VERIFICATION_LABEL[v]}</SelectItem>)}
          </SelectContent>
        </Select>
        <Button size="sm" variant={onlyUnmatched ? "default" : "outline"} onClick={() => setOnlyUnmatched((v) => !v)}>
          À géocoder
        </Button>
        <span className="text-[11px] text-muted-foreground ml-auto">{filtered.length} / {rows.length}</span>
      </div>

      {loading ? (
        <Card className="p-6 text-center text-sm text-muted-foreground"><Loader2 className="w-4 h-4 inline animate-spin mr-2" /> Chargement…</Card>
      ) : filtered.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucun tronçon.</Card>
      ) : (
        <div className="space-y-2">
          {filtered.map((r) => {
            const unmatched = !r.departure_place_id || !r.destination_place_id;
            return (
              <Card key={r.id} className={`p-3 space-y-2 ${!r.is_active ? "opacity-60" : ""}`}>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="font-semibold text-sm truncate">{r.departure_name} → {r.destination_name}</p>
                    <p className="text-[10px] text-muted-foreground truncate">brut: {r.raw_departure_name} / {r.raw_destination_name}</p>
                  </div>
                  <div className="flex gap-1 shrink-0">
                    <Badge variant="outline" className="text-[10px]">Jour {fmt(r.day_price_gnf)}</Badge>
                    <Badge variant="outline" className="text-[10px]">Nuit {fmt(r.night_price_gnf)}</Badge>
                  </div>
                </div>
                <div className="flex flex-wrap gap-1 items-center">
                  <Badge variant="outline" className="text-[10px]">
                    <ShieldCheck className="w-3 h-3 mr-1" />{VERIFICATION_LABEL[r.verification_status as MapVerificationStatus]}
                  </Badge>
                  <Badge variant="outline" className="text-[10px]">{r.confidence_score}%</Badge>
                  {r.is_bidirectional && <Badge variant="outline" className="text-[10px]">↔</Badge>}
                  {unmatched && (
                    <Badge variant="outline" className="text-[10px] bg-amber-500/15 text-amber-700 dark:text-amber-400">
                      <MapPinOff className="w-3 h-3 mr-1" /> À géocoder
                    </Badge>
                  )}
                  <label className="flex items-center gap-1 text-[11px] ml-auto">
                    <Switch checked={r.is_active} onCheckedChange={(v) => patch(r.id, { is_active: v })} />
                    Actif
                  </label>
                </div>
                <div className="flex flex-wrap gap-1">
                  {VERIFICATIONS.map((v) => (
                    <Button key={v} size="sm" variant="outline" className="h-7 text-[11px]" onClick={() => patch(r.id, { verification_status: v })}>
                      {VERIFICATION_LABEL[v]}
                    </Button>
                  ))}
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </ModulePage>
  );
}