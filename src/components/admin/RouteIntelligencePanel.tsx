import { useCallback, useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Brain, RefreshCw, Loader2, ShieldCheck, Hourglass, Sparkles, XCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface Segment {
  id: number;
  origin_district: string | null;
  destination_district: string | null;
  phase: string | null;
  time_window: string | null;
  day_type: string | null;
  observed_count: number;
  unique_driver_count: number;
  median_duration_s: number | null;
  provider_median_duration_s: number | null;
  average_time_saved_s: number | null;
  deviation_frequency: number | null;
  confidence_score: number;
  status: string;
  last_observed_at: string | null;
}

const STATUS_META: Record<string, { label: string; chip: string; Icon: typeof Hourglass }> = {
  collecting: { label: "Collecte",  chip: "chip-mute",   Icon: Hourglass },
  candidate:  { label: "Candidat",  chip: "chip-info",   Icon: Sparkles },
  trusted:    { label: "Vérifié",   chip: "chip-ok",     Icon: ShieldCheck },
  rejected:   { label: "Rejeté",    chip: "chip-err",    Icon: XCircle },
};

function fmtSec(s: number | null) {
  if (s == null) return "—";
  if (s < 60) return `${s}s`;
  return `${Math.round(s / 60)}m`;
}

/**
 * Route Learning v1 — admin honest intelligence view.
 *
 * Reads aggregated `learned_route_segments` and lets an admin trigger
 * `analyze_route_learning_v1`. No customer exposure, no navigation override.
 */
export function RouteIntelligencePanel() {
  const [rows, setRows] = useState<Segment[]>([]);
  const [loading, setLoading] = useState(true);
  const [running, setRunning] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("learned_route_segments")
      .select("id, origin_district, destination_district, phase, time_window, day_type, observed_count, unique_driver_count, median_duration_s, provider_median_duration_s, average_time_saved_s, deviation_frequency, confidence_score, status, last_observed_at")
      .order("confidence_score", { ascending: false })
      .order("observed_count", { ascending: false })
      .limit(100);
    if (error) {
      toast.error("Lecture des insights impossible");
    } else {
      setRows((data ?? []) as Segment[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const refresh = useCallback(async () => {
    setRunning(true);
    const { data, error } = await supabase.rpc("analyze_route_learning_v1", { p_window_days: 30 });
    setRunning(false);
    if (error) {
      toast.error("Analyse impossible : " + error.message);
      return;
    }
    const r = Array.isArray(data) ? data[0] : data;
    toast.success(`Analyse terminée — ${r?.processed_summaries ?? 0} courses, ${r?.upserted_segments ?? 0} segments mis à jour`);
    await load();
  }, [load]);

  const review = useCallback(async (id: number, status: "candidate" | "trusted" | "rejected") => {
    const { error } = await supabase.rpc("review_learned_route_segment", { p_id: id, p_status: status });
    if (error) toast.error("Action refusée : " + error.message);
    else { toast.success("Segment mis à jour"); await load(); }
  }, [load]);

  const trusted = rows.filter(r => r.status === "trusted").length;
  const candidates = rows.filter(r => r.status === "candidate").length;
  const avgSaved = (() => {
    const ok = rows.filter(r => r.status === "trusted" && (r.average_time_saved_s ?? 0) > 0);
    if (!ok.length) return null;
    return Math.round(ok.reduce((s, r) => s + (r.average_time_saved_s ?? 0), 0) / ok.length);
  })();

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center gap-2 flex-wrap">
        <Brain className="w-4 h-4 text-primary" />
        <h3 className="text-sm font-semibold">Intelligence d'itinéraires v1</h3>
        <span className="chip-status chip-mute text-[10px]">analyse agrégée — pas de navigation active</span>
        <div className="ml-auto">
          <Button size="sm" variant="outline" onClick={refresh} disabled={running}>
            {running ? <Loader2 className="w-3.5 h-3.5 animate-spin mr-1" /> : <RefreshCw className="w-3.5 h-3.5 mr-1" />}
            Lancer l'analyse
          </Button>
        </div>
      </div>

      <p className="text-[11.5px] text-muted-foreground leading-snug">
        Aggrège les trajets terminés par district, phase, créneau horaire et type de jour.
        Les insights restent en lecture admin et n'alimentent pas encore la navigation des chauffeurs ou des clients.
      </p>

      <div className="grid grid-cols-3 gap-2 text-center">
        <KPI label="Vérifiés" value={trusted} />
        <KPI label="Candidats" value={candidates} />
        <KPI label="Gain moyen vérifié" value={avgSaved != null ? fmtSec(avgSaved) : "—"} />
      </div>

      {loading ? (
        <div className="text-xs text-muted-foreground italic">Chargement…</div>
      ) : rows.length === 0 ? (
        <div className="text-xs text-muted-foreground italic border border-dashed rounded-md p-3 text-center">
          Aucune donnée suffisante pour proposer des itinéraires locaux. La collecte continue.
        </div>
      ) : (
        <div className="space-y-1.5">
          {rows.map((r) => {
            const meta = STATUS_META[r.status] ?? STATUS_META.collecting;
            const SIcon = meta.Icon;
            const saved = r.average_time_saved_s ?? 0;
            return (
              <div key={r.id} className="admin-card p-2.5">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-mono text-[12px] font-medium">
                    {r.origin_district ?? "—"} → {r.destination_district ?? "—"}
                  </span>
                  <span className={`chip-status ${meta.chip}`}>
                    <SIcon className="w-3 h-3 -ml-0.5" /> {meta.label}
                  </span>
                  <span className="chip-status chip-mute text-[10px]">{r.phase ?? "—"}</span>
                  <span className="chip-status chip-mute text-[10px]">{r.time_window ?? "—"}</span>
                  <span className="chip-status chip-mute text-[10px]">{r.day_type ?? "—"}</span>
                  <span className="ml-auto text-[10px] font-mono text-muted-foreground">
                    conf {(r.confidence_score * 100).toFixed(0)}%
                  </span>
                </div>
                <div className="mt-1 grid grid-cols-2 sm:grid-cols-4 gap-1 text-[11px] font-mono text-muted-foreground">
                  <span>obs {r.observed_count}</span>
                  <span>chauffeurs {r.unique_driver_count}</span>
                  <span>réel {fmtSec(r.median_duration_s)} / fournisseur {fmtSec(r.provider_median_duration_s)}</span>
                  <span>{saved > 0 ? `gain ${fmtSec(saved)}` : "pas de gain"} · dév {Math.round((r.deviation_frequency ?? 0) * 100)}%</span>
                </div>
                {r.status !== "rejected" && (
                  <div className="mt-2 flex gap-1.5">
                    {r.status !== "candidate" && (
                      <Button size="sm" variant="ghost" className="h-6 text-[11px] px-2" onClick={() => review(r.id, "candidate")}>
                        Candidat
                      </Button>
                    )}
                    {r.status !== "trusted" && r.observed_count >= 10 && r.unique_driver_count >= 3 && (
                      <Button size="sm" variant="ghost" className="h-6 text-[11px] px-2" onClick={() => review(r.id, "trusted")}>
                        Marquer vérifié
                      </Button>
                    )}
                    <Button size="sm" variant="ghost" className="h-6 text-[11px] px-2 text-destructive" onClick={() => review(r.id, "rejected")}>
                      Rejeter
                    </Button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      <p className="text-[10px] text-muted-foreground/80 italic">
        Apprentissage uniquement — pas utilisé pour la navigation. Les trajets restent guidés par le fournisseur cartographique.
      </p>
    </Card>
  );
}

function KPI({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="rounded-md bg-muted/40 p-2">
      <div className="text-[10px] uppercase tracking-wider text-muted-foreground/80">{label}</div>
      <div className="text-base font-semibold tabular-nums mt-0.5">{value}</div>
    </div>
  );
}