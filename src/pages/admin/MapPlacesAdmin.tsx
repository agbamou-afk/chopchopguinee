import { useEffect, useMemo, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/hooks/use-toast";
import {
  listPlaces, updatePlaceVerification, VERIFICATION_LABEL,
  listMerchantLocationSubmissions, adminSetMerchantLocationStatus,
  MERCHANT_LOC_LABEL,
  type MapVerificationStatus, type MerchantLocationStatus,
} from "@/lib/maps/canonical";
import { Loader2, ShieldCheck, AlertTriangle, Store as StoreIcon } from "lucide-react";

const VERIFICATIONS: MapVerificationStatus[] = [
  "unverified","submitted","field_checked","admin_verified","trusted","needs_review","duplicate","closed",
];

function tone(s: string) {
  if (s === "trusted" || s === "admin_verified") return "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400";
  if (s === "needs_review") return "bg-orange-500/15 text-orange-700 dark:text-orange-400";
  if (s === "duplicate" || s === "closed") return "bg-muted text-muted-foreground";
  return "bg-blue-500/15 text-blue-700 dark:text-blue-400";
}

export default function MapPlacesAdmin() {
  const [places, setPlaces] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState("");
  const [filterVerif, setFilterVerif] = useState<string>("all");
  const [trustedOnly, setTrustedOnly] = useState(false);
  const [tab, setTab] = useState<"all" | "merchants">("all");
  const [subs, setSubs] = useState<any[]>([]);
  const [subsLoading, setSubsLoading] = useState(false);

  async function refresh() {
    setLoading(true);
    try { setPlaces(await listPlaces()); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
    finally { setLoading(false); }
  }
  async function refreshSubs() {
    setSubsLoading(true);
    try { setSubs(await listMerchantLocationSubmissions()); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
    finally { setSubsLoading(false); }
  }
  useEffect(() => { refresh(); refreshSubs(); }, []);

  const filtered = useMemo(() => places.filter((p) => {
    if (filterVerif !== "all" && p.verification_status !== filterVerif) return false;
    if (trustedOnly && p.verification_status !== "trusted") return false;
    if (q) {
      const s = q.toLowerCase();
      const hay = [p.name, p.commune, p.neighborhood, p.category].filter(Boolean).join(" ").toLowerCase();
      if (!hay.includes(s)) return false;
    }
    return true;
  }), [places, q, filterVerif, trustedOnly]);

  async function setVerif(id: string, v: MapVerificationStatus) {
    try { await updatePlaceVerification(id, v); toast({ title: "Lieu mis à jour" }); refresh(); }
    catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
  }

  async function setMerchantStatus(storeId: string, status: Exclude<MerchantLocationStatus, "none">) {
    try {
      await adminSetMerchantLocationStatus(storeId, status);
      toast({ title: "Soumission mise à jour" });
      refreshSubs(); refresh();
    } catch (e: any) { toast({ title: "Erreur", description: e.message, variant: "destructive" }); }
  }

  return (
    <ModulePage module="zones" title="Carte — Lieux" subtitle="map_places · intelligence des lieux & vérification">
      <div className="flex gap-2">
        <Button size="sm" variant={tab === "all" ? "default" : "outline"} onClick={() => setTab("all")}>Tous les lieux</Button>
        <Button size="sm" variant={tab === "merchants" ? "default" : "outline"} onClick={() => setTab("merchants")}>
          <StoreIcon className="w-3.5 h-3.5 mr-1" /> Soumissions marchands
        </Button>
      </div>

      {tab === "merchants" ? (
        subsLoading ? (
          <Card className="p-6 text-center text-sm text-muted-foreground"><Loader2 className="w-4 h-4 inline animate-spin mr-2" /> Chargement…</Card>
        ) : subs.length === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucune soumission marchand.</Card>
        ) : (
          <div className="grid gap-2 md:grid-cols-2">
            {subs.map((s) => {
              const st = (s.location_submission_status ?? "submitted") as MerchantLocationStatus;
              return (
                <Card key={s.id} className="p-3 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">{s.name}</p>
                      <p className="text-[11px] text-muted-foreground truncate">
                        {[s.commune, s.district].filter(Boolean).join(" · ") || "—"}
                      </p>
                      <p className="text-[11px] text-muted-foreground mt-0.5">
                        {Number.isFinite(s.latitude) && Number.isFinite(s.longitude)
                          ? `${(s.latitude as number).toFixed(5)}, ${(s.longitude as number).toFixed(5)}`
                          : "—"}
                      </p>
                      {s.landmark_note && (
                        <p className="text-[11px] text-muted-foreground mt-0.5">Repère : {s.landmark_note}</p>
                      )}
                      {s.location_submitted_at && (
                        <p className="text-[10px] text-muted-foreground mt-0.5">
                          Soumis le {new Date(s.location_submitted_at).toLocaleString("fr-FR")}
                        </p>
                      )}
                    </div>
                    <Badge variant="outline" className={`text-[10px] ${tone(
                      st === "trusted" || st === "admin_verified" ? "trusted"
                      : st === "needs_review" ? "needs_review"
                      : st === "rejected" ? "closed" : "submitted",
                    )}`}>
                      <ShieldCheck className="w-3 h-3 mr-1" />{MERCHANT_LOC_LABEL[st]}
                    </Badge>
                  </div>
                  {!s.map_place_id && (
                    <Badge variant="outline" className="text-[10px] bg-amber-500/15 text-amber-700 dark:text-amber-400">
                      <AlertTriangle className="w-3 h-3 mr-1" /> Lieu non lié
                    </Badge>
                  )}
                  <div className="flex flex-wrap gap-1 pt-1">
                    {(["admin_verified","trusted","needs_review","rejected"] as Exclude<MerchantLocationStatus,"none">[]).map((v) => (
                      <Button key={v} size="sm" variant="outline" className="h-7 text-[11px]" onClick={() => setMerchantStatus(s.id, v)}>
                        {MERCHANT_LOC_LABEL[v]}
                      </Button>
                    ))}
                  </div>
                </Card>
              );
            })}
          </div>
        )
      ) : (
      <>
      <div className="flex flex-wrap gap-2 items-center">
        <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Recherche…" className="w-56 h-8 text-xs" />
        <Select value={filterVerif} onValueChange={setFilterVerif}>
          <SelectTrigger className="w-[180px] h-8 text-xs"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Toutes vérifications</SelectItem>
            {VERIFICATIONS.map((v) => <SelectItem key={v} value={v}>{VERIFICATION_LABEL[v]}</SelectItem>)}
          </SelectContent>
        </Select>
        <Button size="sm" variant={trustedOnly ? "default" : "outline"} onClick={() => setTrustedOnly((v) => !v)}>Confiance uniquement</Button>
      </div>

      {loading ? (
        <Card className="p-6 text-center text-sm text-muted-foreground"><Loader2 className="w-4 h-4 inline animate-spin mr-2" /> Chargement…</Card>
      ) : filtered.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">Aucun lieu enregistré.</Card>
      ) : (
        <div className="grid gap-2 md:grid-cols-2">
          {filtered.map((p) => (
            <Card key={p.id} className="p-3 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-semibold text-sm truncate">{p.name}</p>
                  <p className="text-[11px] text-muted-foreground truncate">
                    {[p.category, p.commune, p.neighborhood].filter(Boolean).join(" · ") || "—"}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-1">
                  <Badge variant="outline" className={`text-[10px] ${tone(p.verification_status)}`}>
                    <ShieldCheck className="w-3 h-3 mr-1" />{VERIFICATION_LABEL[p.verification_status as MapVerificationStatus]}
                  </Badge>
                  <span className="text-[10px] text-muted-foreground">Confiance {p.confidence_score}%</span>
                </div>
              </div>
              {p.last_reported_at && (
                <Badge variant="outline" className="text-[10px] bg-amber-500/15 text-amber-700 dark:text-amber-400">
                  <AlertTriangle className="w-3 h-3 mr-1" /> Signalement actif
                </Badge>
              )}
              <div className="flex flex-wrap gap-1 pt-1">
                {(["field_checked","admin_verified","trusted","needs_review","duplicate","closed"] as MapVerificationStatus[]).map((v) => (
                  <Button key={v} size="sm" variant="outline" className="h-7 text-[11px]" onClick={() => setVerif(p.id, v)}>
                    {VERIFICATION_LABEL[v]}
                  </Button>
                ))}
              </div>
            </Card>
          ))}
        </div>
      )}
      </>
      )}
    </ModulePage>
  );
}