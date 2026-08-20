import { useEffect, useState } from "react";
import { Activity, TrendingDown, TrendingUp } from "lucide-react";
import { formatGNF } from "@/lib/marche";
import {
  baseUnitLabel,
  confidenceLabelFr,
  freshnessLabelFr,
  getObservedPrices,
  pickVariantCohort,
  type ObservedPriceCohort,
} from "@/lib/marche/priceIntelligence";

interface Props {
  commodityCode: string;
  variantCode: string;
  /** Commune used to scope the cohort. Omit for the all-zones read. */
  zone?: string | null;
  className?: string;
}

/**
 * R8 — "Prix observé sur ChopChop".
 * Renders ONLY what the server observed. Never predicts, never invents a number
 * when the cohort is too thin: in that case it says so in plain French.
 */
export function ObservedPriceBadge({ commodityCode, variantCode, zone, className }: Props) {
  const [cohort, setCohort] = useState<ObservedPriceCohort | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    getObservedPrices(commodityCode, zone ?? null)
      .then((read) => {
        if (!alive) return;
        setCohort(pickVariantCohort(read, variantCode));
        setLoading(false);
      })
      .catch(() => {
        if (!alive) return;
        setCohort(null);
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [commodityCode, variantCode, zone]);

  if (loading) {
    return (
      <div className={`h-5 w-40 rounded-full bg-muted animate-pulse ${className ?? ""}`} aria-hidden />
    );
  }

  if (!cohort || cohort.insufficient_data || cohort.median_gnf == null) {
    return (
      <p className={`text-[10px] leading-snug text-muted-foreground ${className ?? ""}`}>
        Pas encore assez de relevés pour afficher un prix observé.
      </p>
    );
  }

  const unit = baseUnitLabel(cohort.canonical_base_unit);
  const mv = cohort.movement;
  const up = (mv?.delta_gnf ?? 0) > 0;

  return (
    <div className={`space-y-1 ${className ?? ""}`}>
      <div className="inline-flex items-center gap-1.5 rounded-full bg-secondary/20 px-2.5 py-1">
        <Activity className="w-3 h-3 text-foreground" />
        <span className="text-[11px] font-semibold text-foreground">
          {formatGNF(cohort.median_gnf)}
          {unit ? ` / ${unit}` : ""}
        </span>
        <span className="text-[10px] text-muted-foreground">observé sur ChopChop</span>
      </div>
      {cohort.p25_gnf != null && cohort.p75_gnf != null && (
        <p className="text-[10px] text-muted-foreground">
          Fourchette observée {formatGNF(cohort.p25_gnf)} – {formatGNF(cohort.p75_gnf)}
          {unit ? ` / ${unit}` : ""}
        </p>
      )}
      <p className="text-[10px] text-muted-foreground">
        {cohort.sample_count} relevé{cohort.sample_count > 1 ? "s" : ""} ·{" "}
        {confidenceLabelFr(cohort.confidence)} · {freshnessLabelFr(cohort.freshness)}
      </p>
      {mv?.comparable && mv.delta_pct != null && (
        <p
          className={`inline-flex items-center gap-1 text-[10px] font-medium ${
            up ? "text-destructive" : "text-success"
          }`}
        >
          {up ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
          {up ? "+" : ""}
          {mv.delta_pct}% sur la période observée
        </p>
      )}
      <p className="text-[9px] italic text-muted-foreground">
        Prix constaté, pas un prix officiel ni garanti.
      </p>
    </div>
  );
}