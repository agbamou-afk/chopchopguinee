import { useEffect, useRef } from "react";
import { MapPin, Loader2, AlertTriangle, Settings, RefreshCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useGeolocation, type GeoStatus } from "@/hooks/useGeolocation";

interface Props {
  /** Called whenever a usable position is acquired (ready or low_accuracy). */
  onLocated: (pos: { lat: number; lng: number; accuracy: number }) => void;
  /** Called when the user opts out and wants to enter their position manually. */
  onManualEntry?: () => void;
  /** When true, render compact / inline. */
  compact?: boolean;
}

const COPY = "CHOP CHOP utilise votre position pour trouver des chauffeurs proches.";

function statusTitle(status: GeoStatus): string {
  switch (status) {
    case "loading":
      return "Recherche de votre position…";
    case "low_accuracy":
      return "Position approximative";
    case "denied":
      return "Autorisation refusée";
    case "blocked":
      return "Géolocalisation bloquée";
    case "unavailable":
      return "Position indisponible";
    default:
      return "Activer la géolocalisation";
  }
}

/**
 * One screen-card that walks the user through every geolocation state:
 * first request → loading → ready / low accuracy / denied / blocked /
 * unavailable. Includes retry, "open settings", and manual fallback CTAs.
 */
export function LocationPermissionPrompt({ onLocated, onManualEntry, compact }: Props) {
  const { status, position, error, request, isReady, isLowAccuracy, supported } =
    useGeolocation();

  const lastTsRef = useRef<number | null>(null);
  useEffect(() => {
    if (!position) return;
    if (!(isReady || isLowAccuracy)) return;
    if (lastTsRef.current === position.timestamp) return;
    lastTsRef.current = position.timestamp;
    onLocated({ lat: position.lat, lng: position.lng, accuracy: position.accuracy });
  }, [position, isReady, isLowAccuracy, onLocated]);

  const Icon =
    status === "loading"
      ? Loader2
      : status === "low_accuracy" || status === "unavailable"
        ? AlertTriangle
        : status === "blocked" || status === "denied"
          ? Settings
          : MapPin;

  const isError =
    status === "denied" || status === "blocked" || status === "unavailable";
  const tone = isError
    ? "border-destructive/30 bg-destructive/5"
    : isLowAccuracy
      ? "border-amber-500/30 bg-amber-500/5"
      : "border-border bg-card";

  const padding = compact ? "p-3" : "p-5";

  return (
    <div className={`rounded-2xl border ${tone} ${padding} space-y-3`}>
      <div className="flex items-start gap-3">
        <div className="rounded-full bg-muted p-2">
          <Icon
            className={`h-5 w-5 ${
              status === "loading" ? "animate-spin text-primary" : "text-foreground"
            }`}
          />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold">{statusTitle(status)}</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {status === "blocked"
              ? "Activez la position dans les réglages du navigateur, puis réessayez."
              : status === "denied"
                ? "Vous pouvez réessayer ou saisir votre position manuellement."
                : status === "low_accuracy" && position
                  ? `Précision ~${Math.round(position.accuracy)} m. Confirmez votre position.`
                  : status === "unavailable"
                    ? error ?? "GPS indisponible. Réessayez ou saisissez l'adresse."
                    : COPY}
          </p>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {!isReady && status !== "loading" && supported && (
          <Button size="sm" onClick={request} className="gap-1.5">
            <RefreshCcw className="h-3.5 w-3.5" />
            {status === "idle" ? "Autoriser" : "Réessayer"}
          </Button>
        )}
        {status === "blocked" && (
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              // No reliable cross-browser API, surface the help link
              window.open(
                "https://support.google.com/chrome/answer/142065",
                "_blank",
                "noopener",
              );
            }}
            className="gap-1.5"
          >
            <Settings className="h-3.5 w-3.5" />
            Ouvrir les réglages
          </Button>
        )}
        {onManualEntry && (
          <Button size="sm" variant="ghost" onClick={onManualEntry}>
            Saisir manuellement
          </Button>
        )}
      </div>
    </div>
  );
}