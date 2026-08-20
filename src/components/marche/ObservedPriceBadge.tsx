import { TrendingDown, TrendingUp } from "lucide-react";
import {
  confidenceLabel,
  formatGnf,
  freshnessLabel,
  zoneLabel,
  type PriceCohort,
} from "@/lib/marche/priceIntelligence";

/**
 * Node 4 — Marché R8: "Prix observé sur ChopChop".
 * Renders ONLY server-derived observation truth. Never a quote, never an
 * estimate, never a price the customer can rely on for a purchase.
 */
export function ObservedPriceBadge({ cohort }: { cohort: PriceCohort | null }) {
  if (!cohort) {
    return (
      <p data-testid="observed-price-none" className="text-[10px] text-muted-foreground">
        Prix observé sur ChopChop : pas encore d'observation.
      </p>
    );
  }

  const zone = zoneLabel(cohort.zone);

  if (cohort.insufficient_data) {
    return (
      <div
        data-testid="observed-price-insufficient"
        className="rounded-xl border border-dashed border-border bg-muted/30 px-3 py-2"
      >
        <p className="text-[10px] font-semibold text-muted-foreground">Prix observé sur ChopChop</p>
        <p className="mt-0.5 text-[10px] text-muted-foreground">
          Données insuffisantes pour publier un prix observé ({cohort.sample_count} observation
          {cohort.sample_count > 1 ? "s" : ""}
          {cohort.min_samples ? ` sur ${cohort.min_samples} requises` : ""}).
        </p>
        {zone && <p className="mt-0.5 text-[10px] text-muted-foreground">{zone}</p>}
      </div>
    );
  }

  const unit = cohort.canonical_base_unit === "l" ? "L" : cohort.canonical_base_unit;
  const mv = cohort.movement;
  const delta = mv?.comparable ? (mv.delta_gnf ?? 0) : null;

  return (
    <div
      data-testid="observed-price"
      className="rounded-xl border border-border/60 bg-muted/30 px-3 py-2 space-y-1"
    >
      <div className="flex items-center justify-between gap-2">
        <p className="text-[10px] font-semibold text-muted-foreground">Prix observé sur ChopChop</p>
        <span data-testid="observed-price-confidence" className="text-[10px] text-muted-foreground">
          {confidenceLabel(cohort.confidence)}
        </span>
      </div>
      <p className="text-sm font-semibold text-foreground">
        {formatGnf(cohort.median_gnf)} <span className="text-[10px] font-normal">/ {unit}</span>
      </p>
      <p className="text-[10px] text-muted-foreground">
        Fourchette {formatGnf(cohort.p25_gnf)} – {formatGnf(cohort.p75_gnf)} ·{" "}
        {cohort.sample_count} observation{cohort.sample_count > 1 ? "s" : ""}
      </p>
      {zone && (
        <p data-testid="observed-price-zone" className="text-[10px] text-muted-foreground">
          {zone}
        </p>
      )}
      <p data-testid="observed-price-freshness" className="text-[10px] text-muted-foreground">
        {freshnessLabel(cohort.freshness)}
      </p>
      {delta != null && delta !== 0 && (
        <p
          data-testid="observed-price-movement"
          className="flex items-center gap-1 text-[10px] text-muted-foreground"
        >
          {delta > 0 ? (
            <TrendingUp className="w-3 h-3" />
          ) : (
            <TrendingDown className="w-3 h-3" />
          )}
          {delta > 0 ? "+" : ""}
          {formatGnf(Math.abs(delta))} sur la période
        </p>
      )}
    </div>
  );
}