import { MapPinOff, RefreshCw, ArrowRight } from "lucide-react";
import { cn } from "@/lib/utils";

interface DegradedMapPanelProps {
  pickupLabel?: string | null;
  dropoffLabel?: string | null;
  distanceLabel?: string | null;
  etaLabel?: string | null;
  zoneLabel?: string | null;
  nearbyPlaces?: { id: string; name: string; sub?: string | null }[];
  message?: string | null;
  onRetry?: () => void;
  onContinue?: () => void;
  continueLabel?: string;
  className?: string;
}

/**
 * Map Phase 2H — Calm degraded-state panel.
 *
 * Replaces a broken/blank map with the operational essentials so the
 * user can keep going: pickup/dropoff text, distance/ETA estimate,
 * zone label, and a short nearby-places list. Never blocks the flow.
 */
export function DegradedMapPanel({
  pickupLabel, dropoffLabel, distanceLabel, etaLabel, zoneLabel,
  nearbyPlaces, message, onRetry, onContinue, continueLabel = "Continuer sans carte",
  className,
}: DegradedMapPanelProps) {
  return (
    <div className={cn(
      "relative rounded-2xl border border-border/60 bg-card/80 p-4 flex flex-col gap-3",
      className,
    )}>
      <div className="flex items-start gap-2">
        <MapPinOff className="w-4 h-4 text-muted-foreground mt-0.5" aria-hidden />
        <div className="flex-1">
          <div className="text-xs font-semibold uppercase tracking-[0.16em] text-foreground">
            Carte indisponible
          </div>
          {message && (
            <div className="text-xs text-muted-foreground mt-0.5">{message}</div>
          )}
        </div>
      </div>

      {(pickupLabel || dropoffLabel) && (
        <div className="rounded-lg bg-muted/40 p-3 text-sm flex items-center gap-2 flex-wrap">
          <span className="font-medium">{pickupLabel ?? "Départ"}</span>
          <ArrowRight className="w-3.5 h-3.5 text-muted-foreground" />
          <span className="font-medium">{dropoffLabel ?? "Destination"}</span>
        </div>
      )}

      {(distanceLabel || etaLabel || zoneLabel) && (
        <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
          {distanceLabel && <span>📏 {distanceLabel}</span>}
          {etaLabel && <span>⏱ {etaLabel}</span>}
          {zoneLabel && <span>📍 {zoneLabel}</span>}
        </div>
      )}

      {nearbyPlaces && nearbyPlaces.length > 0 && (
        <div>
          <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1">
            Lieux connus à proximité
          </div>
          <ul className="text-xs space-y-1">
            {nearbyPlaces.slice(0, 5).map((p) => (
              <li key={p.id} className="flex items-baseline gap-1.5">
                <span className="text-foreground">{p.name}</span>
                {p.sub && <span className="text-muted-foreground">— {p.sub}</span>}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="flex flex-wrap gap-2 pt-1">
        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="inline-flex items-center gap-1.5 h-8 px-3 rounded-full border border-border/60 bg-card text-xs font-semibold hover:bg-muted transition"
          >
            <RefreshCw className="w-3.5 h-3.5" /> Réessayer la carte
          </button>
        )}
        {onContinue && (
          <button
            type="button"
            onClick={onContinue}
            className="inline-flex items-center gap-1.5 h-8 px-3 rounded-full bg-primary text-primary-foreground text-xs font-semibold hover:opacity-90 transition"
          >
            {continueLabel}
          </button>
        )}
      </div>
    </div>
  );
}