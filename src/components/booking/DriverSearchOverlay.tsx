import { useEffect, useState } from "react";
import { Bike, X, RotateCcw, CheckCircle2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export type SearchPhase = "searching" | "matched" | "no_driver" | "error";

interface MatchedDriver {
  id: string;
  name: string;
  rating?: number | null;
  vehicle?: string | null;
  etaSeconds: number;
  photoUrl?: string | null;
}

interface Props {
  open: boolean;
  phase: SearchPhase;
  serviceType: "moto" | "toktok";
  driver?: MatchedDriver | null;
  onCancel: () => void;
  onRetry?: () => void;
  onConfirmMatch?: () => void;
}

/**
 * Full-screen overlay shown after the user requests a ride.
 * Animates a CHOP-branded search pulse, then resolves to a matched
 * driver card or a "no driver available" state with retry.
 */
export function DriverSearchOverlay({
  open,
  phase,
  serviceType,
  driver,
  onCancel,
  onRetry,
  onConfirmMatch,
}: Props) {
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    if (!open || phase !== "searching") {
      setElapsed(0);
      return;
    }
    const start = Date.now();
    const t = window.setInterval(() => {
      setElapsed(Math.floor((Date.now() - start) / 1000));
    }, 1000);
    return () => window.clearInterval(t);
  }, [open, phase]);

  // Fire analytics on phase transitions
  useEffect(() => {
    if (!open) return;
    if (phase === "searching") {
      try {
        Analytics.track("driver.search.started" as any, {
          metadata: { service_type: serviceType },
        });
      } catch {}
    } else if (phase === "matched") {
      try {
        Analytics.track("driver.search.matched" as any, {
          metadata: {
            service_type: serviceType,
            eta_seconds: driver?.etaSeconds ?? null,
          },
        });
      } catch {}
    } else if (phase === "no_driver" || phase === "error") {
      try {
        Analytics.track("driver.search.failed" as any, {
          metadata: { service_type: serviceType, reason: phase },
        });
      } catch {}
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, phase]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 bg-background/95 backdrop-blur-sm flex flex-col">
      <div className="flex items-center justify-between p-4 border-b border-border">
        <p className="text-sm font-semibold">
          {phase === "searching" && "Recherche de chauffeurs…"}
          {phase === "matched" && "Chauffeur trouvé"}
          {phase === "no_driver" && "Aucun chauffeur"}
          {phase === "error" && "Erreur"}
        </p>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-full p-1.5 hover:bg-muted"
          aria-label="Annuler"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center px-6 text-center">
        {phase === "searching" && (
          <>
            <div className="relative h-32 w-32 mb-6">
              <span className="absolute inset-0 rounded-full bg-primary/20 animate-ping" />
              <span className="absolute inset-3 rounded-full bg-primary/30 animate-ping [animation-delay:300ms]" />
              <span className="absolute inset-6 rounded-full bg-primary/40 animate-pulse" />
              <div className="absolute inset-0 flex items-center justify-center">
                <div className="rounded-full bg-primary p-4 shadow-lg">
                  <Bike className="h-8 w-8 text-primary-foreground" />
                </div>
              </div>
            </div>
            <p className="text-base font-medium">
              Recherche de chauffeurs proches…
            </p>
            <p className="text-xs text-muted-foreground mt-1 tabular-nums">
              {elapsed}s écoulées
            </p>
          </>
        )}

        {phase === "matched" && driver && (
          <>
            <div className="mb-4 rounded-full bg-emerald-500/10 p-4">
              <CheckCircle2 className="h-10 w-10 text-emerald-600" />
            </div>
            <div className="rounded-2xl border border-border bg-card p-4 w-full max-w-xs">
              <div className="flex items-center gap-3">
                <div className="h-12 w-12 rounded-full bg-muted overflow-hidden flex items-center justify-center text-base font-semibold">
                  {driver.photoUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element, jsx-a11y/alt-text
                    <img src={driver.photoUrl} className="h-full w-full object-cover" />
                  ) : (
                    driver.name.slice(0, 1).toUpperCase()
                  )}
                </div>
                <div className="flex-1 min-w-0 text-left">
                  <p className="text-sm font-semibold truncate">{driver.name}</p>
                  <p className="text-xs text-muted-foreground truncate">
                    {driver.vehicle ?? "Moto"}
                    {driver.rating != null && ` • ★ ${driver.rating.toFixed(1)}`}
                  </p>
                </div>
              </div>
              <div className="mt-3 flex items-center justify-between rounded-xl bg-primary/10 px-3 py-2">
                <span className="text-xs font-medium">Arrive dans</span>
                <span className="text-base font-bold text-primary tabular-nums">
                  {Math.max(1, Math.round(driver.etaSeconds / 60))} min
                </span>
              </div>
              <Button
                className="mt-3 w-full"
                onClick={onConfirmMatch}
              >
                Voir le trajet
              </Button>
            </div>
          </>
        )}

        {(phase === "no_driver" || phase === "error") && (
          <>
            <div className="mb-4 rounded-full bg-amber-500/10 p-4">
              <AlertTriangle className="h-10 w-10 text-amber-600" />
            </div>
            <p className="text-base font-medium">
              {phase === "no_driver"
                ? "Aucun chauffeur disponible pour le moment."
                : "Une erreur est survenue."}
            </p>
            <p className="text-xs text-muted-foreground mt-1 max-w-xs">
              {phase === "no_driver"
                ? "Réessayez dans un instant ou ajustez votre point de départ."
                : "Vérifiez votre connexion et réessayez."}
            </p>
            <div className="mt-6 flex gap-2">
              {onRetry && (
                <Button onClick={onRetry} className="gap-1.5">
                  <RotateCcw className="h-4 w-4" />
                  Réessayer
                </Button>
              )}
              <Button variant="outline" onClick={onCancel}>
                Annuler
              </Button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}