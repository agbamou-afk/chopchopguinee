import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { CheckCircle2, Circle, Loader2, MapPin, Phone, Receipt, RefreshCw, WifiOff } from "lucide-react";
import {
  getRepasTracking,
  repasTrackingLabel,
  customerCustodyKind,
  REPAS_MISSION_LABEL,
  type RepasTracking,
} from "@/lib/repas/tracking";
import { CustodyCodeCard } from "@/components/repas/CustodyCodeCard";
import { repasLocationQualityLabel } from "@/lib/repas/destinationDraft";
import { useAppEnv } from "@/contexts/AppEnvContext";
import { formatGNF } from "@/lib/format";
import type { FoodOrderState } from "@/lib/repas/types";

const DELIVERY_STEPS: FoodOrderState[] = ["placed", "confirmed", "preparing", "ready", "out_for_delivery", "completed"];
const PICKUP_STEPS: FoodOrderState[] = ["placed", "confirmed", "preparing", "ready", "completed"];

/** Bounded fallback refresh when realtime is unavailable — never unbounded. */
const FALLBACK_POLL_MS = 20000;
const FALLBACK_POLL_MAX = 45;

/**
 * R7 — canonical customer tracking surface.
 *
 * Every status, amount and affordance comes from `repas_order_tracking`.
 * Reconnect-safe: the panel refetches on realtime change and on remount, so a
 * killed app or a lost network never leaves the customer on a stale state.
 *
 * R11 — on a low-data or dropped Conakry connection the panel says so plainly
 * and falls back to a bounded refresh instead of silently freezing.
 */
export function RepasOrderTrackingPanel({
  orderId,
  onOpenReceipt,
}: {
  orderId: string;
  onOpenReceipt?: () => void;
}) {
  const [tracking, setTracking] = useState<RepasTracking | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [live, setLive] = useState(false);
  const [lastSyncedAt, setLastSyncedAt] = useState<number | null>(null);
  const pollCount = useRef(0);
  const { online } = useAppEnv();

  const load = useCallback(async () => {
    setBusy(true);
    try {
      setTracking(await getRepasTracking(orderId));
      setError(null);
      setLastSyncedAt(Date.now());
    } catch (e) {
      setError(e instanceof Error ? e.message : "Suivi indisponible.");
    } finally {
      setBusy(false);
    }
  }, [orderId]);

  useEffect(() => {
    void load();
  }, [load]);

  // Reconnect-safe live truth: any server-side change re-pulls the read model.
  useEffect(() => {
    const channel = supabase
      .channel(`repas-tracking-${orderId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "food_orders", filter: `id=eq.${orderId}` },
        () => void load(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "missions", filter: `ref_food_order_id=eq.${orderId}` },
        () => void load(),
      )
      .subscribe((status) => setLive(status === "SUBSCRIBED"));
    return () => {
      setLive(false);
      void supabase.removeChannel(channel);
    };
  }, [orderId, load]);

  // A restored connection must immediately re-read canonical truth.
  useEffect(() => {
    if (online) void load();
  }, [online, load]);

  // Bounded fallback: only while the live channel is down and the order is open.
  useEffect(() => {
    if (live || !online) return;
    if (!tracking || tracking.terminal) return;
    pollCount.current = 0;
    const t = setInterval(() => {
      if (pollCount.current >= FALLBACK_POLL_MAX) {
        clearInterval(t);
        return;
      }
      pollCount.current += 1;
      void load();
    }, FALLBACK_POLL_MS);
    return () => clearInterval(t);
  }, [live, online, tracking?.terminal, load]);

  if (!tracking && !error) {
    return <Skeleton className="h-32 w-full rounded-2xl" />;
  }

  if (error || !tracking) {
    return (
      <div className="rounded-2xl border border-border/60 px-4 py-3 space-y-2">
        <p className="text-sm text-muted-foreground">{error}</p>
        <Button size="sm" variant="outline" className="rounded-xl" onClick={() => void load()}>
          <RefreshCw className="w-3.5 h-3.5 mr-1.5" /> Réessayer
        </Button>
      </div>
    );
  }

  const steps = tracking.fulfillment === "pickup" ? PICKUP_STEPS : DELIVERY_STEPS;
  const currentIndex = steps.indexOf(tracking.state);
  const custodyKind = customerCustodyKind(tracking);
  const destination = tracking.destination ?? null;
  const qualityLabel = repasLocationQualityLabel(destination?.location_quality);
  const degraded = !online || (!live && !tracking.terminal);

  return (
    <div className="space-y-3">
      {degraded && (
        <div
          role="status"
          className="flex items-start gap-2 rounded-2xl bg-muted px-3 py-2 text-[11px] text-muted-foreground"
        >
          <WifiOff className="w-3.5 h-3.5 mt-0.5 shrink-0" />
          <span>
            {online
              ? "Suivi en direct indisponible : mise à jour toutes les 20 secondes."
              : "Hors ligne : dernier état connu affiché."}
            {lastSyncedAt && (
              <>
                {" "}
                Dernière mise à jour à{" "}
                {new Date(lastSyncedAt).toLocaleTimeString("fr-FR", {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
                .
              </>
            )}
          </span>
        </div>
      )}

      <div className="rounded-2xl border border-border/60 px-4 py-3">
        <div className="flex items-center justify-between">
          <p className="text-sm font-semibold text-foreground">{repasTrackingLabel(tracking)}</p>
          {busy && <Loader2 className="w-3.5 h-3.5 animate-spin text-muted-foreground" />}
        </div>
        <p className="text-[11px] text-muted-foreground mt-0.5">
          {tracking.restaurant.name}
          {tracking.fulfillment === "pickup" ? " · Retrait sur place" : " · Livraison"}
        </p>

        {tracking.state === "cancelled" ? (
          <p className="mt-3 text-xs text-destructive">
            {tracking.terminal_reason ?? "Commande annulée."}
          </p>
        ) : (
          <ol className="mt-3 space-y-1.5">
            {steps.map((s, i) => {
              const done = currentIndex >= i;
              return (
                <li key={s} className="flex items-center gap-2">
                  {done ? (
                    <CheckCircle2 className="w-3.5 h-3.5 text-success shrink-0" />
                  ) : (
                    <Circle className="w-3.5 h-3.5 text-muted-foreground/50 shrink-0" />
                  )}
                  <span className={`text-xs ${done ? "text-foreground" : "text-muted-foreground"}`}>
                    {repasTrackingLabel({ state: s, fulfillment: tracking.fulfillment })}
                  </span>
                </li>
              );
            })}
          </ol>
        )}

        {tracking.mission && (
          <p className="mt-3 text-[11px] text-muted-foreground">
            {REPAS_MISSION_LABEL[tracking.mission.state] ?? tracking.mission.state}
          </p>
        )}

        {tracking.courier?.full_name && (
          <div className="mt-3 flex items-center justify-between rounded-xl bg-muted/40 px-3 py-2">
            <span className="text-xs font-medium text-foreground">{tracking.courier.full_name}</span>
            {tracking.courier.phone && (
              <a
                href={`tel:${tracking.courier.phone}`}
                className="inline-flex items-center gap-1 text-xs font-semibold text-primary"
              >
                <Phone className="w-3.5 h-3.5" /> Appeler
              </a>
            )}
          </div>
        )}

        {tracking.cash_due_gnf != null && tracking.cash_due_gnf > 0 && (
          <p className="mt-3 text-xs text-foreground">
            À payer en espèces : <strong className="tabular-nums">{formatGNF(tracking.cash_due_gnf)}</strong>
          </p>
        )}
      </div>

      {destination && (
        <div className="rounded-2xl border border-border/60 px-4 py-3">
          <p className="text-[11px] font-semibold text-muted-foreground uppercase tracking-wide">
            Destination
          </p>
          <div className="mt-1.5 flex items-start gap-2">
            <MapPin className="w-3.5 h-3.5 mt-0.5 text-muted-foreground shrink-0" />
            <div className="min-w-0">
              {destination.label && (
                <p className="text-sm text-foreground">{destination.label}</p>
              )}
              {destination.landmark && (
                <p className="text-xs text-muted-foreground">{destination.landmark}</p>
              )}
              {destination.instructions && (
                <p className="text-xs text-muted-foreground mt-1">{destination.instructions}</p>
              )}
              {qualityLabel && (
                <p className="text-[11px] text-muted-foreground mt-1.5">{qualityLabel}</p>
              )}
            </div>
          </div>
          <p className="text-[11px] text-muted-foreground mt-2">
            Cette destination est figée pour cette commande.
          </p>
        </div>
      )}

      {custodyKind && (
        <CustodyCodeCard
          orderId={orderId}
          kind={custodyKind}
          title={custodyKind === "customer_pickup" ? "Code de retrait" : "Code de livraison"}
          instruction={
            custodyKind === "customer_pickup"
              ? "Donnez ce code au restaurant seulement quand vous récupérez la commande."
              : "Donnez ce code au coursier seulement quand vous avez la commande en main."
          }
        />
      )}

      {onOpenReceipt && (
        <Button variant="outline" className="w-full h-11 rounded-2xl justify-start" onClick={onOpenReceipt}>
          <Receipt className="w-4 h-4 mr-2" /> Voir le reçu détaillé
        </Button>
      )}
    </div>
  );
}
