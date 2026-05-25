import { MapPinOff, RefreshCw } from "lucide-react";
import { cn } from "@/lib/utils";

interface Props {
  /** Headline — short, brand-voiced. */
  title?: string;
  /** Secondary explanation shown beneath the title. */
  message?: string;
  /** Optional retry action — e.g., refresh map config. */
  onRetry?: () => void;
  retryLabel?: string;
  className?: string;
}

/**
 * Branded fallback surface used when the map tiles or config cannot load.
 * Keeps the same visual footprint as ChopMap so layouts don't shift.
 */
export function MapFallbackCard({
  title = "Carte CHOPCHOP",
  message = "Mode hors-ligne — la carte sera disponible dès la reconnexion.",
  onRetry,
  retryLabel = "Réessayer",
  className,
}: Props) {
  return (
    <div className={cn("relative chop-map-fallback rounded-2xl overflow-hidden", className)}>
      <div className="absolute inset-0 flex flex-col items-center justify-center text-center px-4 gap-2">
        <MapPinOff className="w-5 h-5 text-muted-foreground" aria-hidden />
        <span className="text-[10px] font-bold uppercase tracking-[0.22em] text-muted-foreground">{title}</span>
        <span className="text-xs text-muted-foreground max-w-[20rem]">{message}</span>
        {onRetry && (
          <button
            type="button" onClick={onRetry}
            className="mt-1 inline-flex items-center gap-1.5 h-8 px-3 rounded-full border border-border/60 bg-card/80 text-xs font-semibold text-foreground hover:bg-card transition"
          >
            <RefreshCw className="w-3.5 h-3.5" /> {retryLabel}
          </button>
        )}
      </div>
    </div>
  );
}
