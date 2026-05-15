import { Bike, Car, Clock, Wallet, AlertTriangle, Loader2, WifiOff } from "lucide-react";
import { formatGNF } from "@/lib/format";
import { formatDistance, formatDuration } from "@/lib/maps";

export type PreviewState = "idle" | "calculating" | "ready" | "unavailable" | "network";

interface Props {
  state: PreviewState;
  serviceType: "moto" | "toktok" | "livraison";
  /** Estimated duration in seconds. */
  durationS?: number;
  /** Estimated distance in meters. */
  distanceM?: number;
  /** Min/max fare bracket in GNF. */
  fareLowGnf?: number;
  fareHighGnf?: number;
  paymentMethod?: "wallet" | "cash";
  onChangePayment?: () => void;
  onRetry?: () => void;
}

const SERVICE_LABEL = { moto: "Moto", toktok: "TokTok", livraison: "Livraison" } as const;
const SERVICE_ICON = { moto: Bike, toktok: Car, livraison: Bike } as const;

/**
 * Booking preview card. Shows ETA + distance + fare bracket, never fakes
 * values: when state is calculating/unavailable/network, the corresponding
 * fields are visually skeleton'd or replaced with copy.
 */
export function EtaPricePreview({
  state,
  serviceType,
  durationS,
  distanceM,
  fareLowGnf,
  fareHighGnf,
  paymentMethod = "wallet",
  onChangePayment,
  onRetry,
}: Props) {
  const Icon = SERVICE_ICON[serviceType];
  const showSkeleton = state === "calculating";

  return (
    <div className="rounded-2xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-center gap-3">
        <div className="rounded-xl bg-primary/10 p-2.5">
          <Icon className="h-5 w-5 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold">{SERVICE_LABEL[serviceType]}</p>
          <p className="text-xs text-muted-foreground">
            {state === "calculating" && "Calcul en cours…"}
            {state === "ready" && distanceM != null && formatDistance(distanceM)}
            {state === "unavailable" && "Itinéraire indisponible"}
            {state === "network" && "Réseau instable"}
            {state === "idle" && "Choisissez votre destination"}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        {/* ETA */}
        <div className="rounded-xl bg-muted/40 px-3 py-2.5">
          <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-wide text-muted-foreground">
            <Clock className="h-3 w-3" />
            ETA
          </div>
          {showSkeleton ? (
            <div className="mt-1 h-5 w-16 rounded bg-muted animate-pulse" />
          ) : state === "ready" && durationS != null ? (
            <p className="mt-0.5 text-base font-bold tabular-nums">
              {formatDuration(durationS)}
            </p>
          ) : (
            <p className="mt-0.5 text-sm text-muted-foreground">—</p>
          )}
        </div>
        {/* Fare bracket */}
        <div className="rounded-xl bg-muted/40 px-3 py-2.5">
          <div className="text-[10px] uppercase tracking-wide text-muted-foreground">
            Prix estimé
          </div>
          {showSkeleton ? (
            <div className="mt-1 h-5 w-20 rounded bg-muted animate-pulse" />
          ) : state === "ready" && fareLowGnf != null && fareHighGnf != null ? (
            <p className="mt-0.5 text-base font-bold tabular-nums">
              {fareLowGnf === fareHighGnf
                ? formatGNF(fareLowGnf)
                : `${formatGNF(fareLowGnf)} – ${formatGNF(fareHighGnf)}`}
            </p>
          ) : (
            <p className="mt-0.5 text-sm text-muted-foreground">—</p>
          )}
        </div>
      </div>

      {(state === "unavailable" || state === "network") && (
        <div className="flex items-center gap-2 rounded-xl border border-amber-500/30 bg-amber-500/5 px-3 py-2 text-xs text-amber-700 dark:text-amber-400">
          {state === "network" ? (
            <WifiOff className="h-3.5 w-3.5 shrink-0" />
          ) : (
            <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
          )}
          <span className="flex-1">
            {state === "network"
              ? "Connexion instable. Réessayez dans un instant."
              : "Aucun itinéraire trouvé. Vérifiez la destination."}
          </span>
          {onRetry && (
            <button
              type="button"
              onClick={onRetry}
              className="font-semibold underline-offset-2 hover:underline"
            >
              Réessayer
            </button>
          )}
        </div>
      )}

      {state === "calculating" && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
          Calcul de l'itinéraire…
        </div>
      )}

      <button
        type="button"
        onClick={onChangePayment}
        className="flex w-full items-center justify-between rounded-xl border border-border px-3 py-2 text-left text-xs hover:border-primary transition-colors"
      >
        <span className="flex items-center gap-2">
          <Wallet className="h-3.5 w-3.5" />
          {paymentMethod === "wallet" ? "CHOPWallet" : "Espèces à la livraison"}
        </span>
        <span className="text-muted-foreground">Modifier</span>
      </button>
    </div>
  );
}