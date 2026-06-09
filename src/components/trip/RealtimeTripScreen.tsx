import { motion } from "framer-motion";
import { X } from "lucide-react";
import { ActiveTripMap } from "./ActiveTripMap";
import { ClientTripReceipt } from "./ClientTripReceipt";
import { PickupConfirmCard } from "./PickupConfirmCard";
import { useRideRealtime } from "@/hooks/useRideRealtime";
import { useRideLifecycleNotifications } from "@/hooks/useRideLifecycleNotifications";
import { useConnectionRestored } from "@/hooks/useConnectionRestored";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { useEffect, useRef, useState } from "react";
import { RidePhaseChip, deriveRidePhase } from "@/components/ride/RidePhaseChip";
import { TrustCues } from "@/components/trust/TrustCues";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface Props {
  rideId: string;
  mode: "moto" | "toktok" | "food";
  /** Wallet hold to release if the user cancels before pickup. */
  holdId?: string | null;
  /** Close the dashboard but keep the ride active in the background.
   * Use this for the header "X": the customer can reopen from
   * Dernière activité → "Course en cours". */
  onClose: () => void;
  /** Explicit cancellation (releases hold + cancels ride server-side). */
  onCancel?: () => void;
}

const TITLES: Record<Props["mode"], string> = {
  moto: "Moto · Suivi en direct",
  toktok: "TokTok · Suivi en direct",
  food: "Repas · Suivi en direct",
};

/**
 * Full-screen realtime trip experience that replaces the legacy LiveTracking
 * in the v2 flow. Pure presentation around <ActiveTripMap>, plus header,
 * call/cancel side effects and wallet release on cancel.
 */
export function RealtimeTripScreen({ rideId, mode, holdId, onClose, onCancel }: Props) {
  const settled = useRef(false);
  const { ride } = useRideRealtime(rideId);
  useRideLifecycleNotifications(ride, "client");
  useConnectionRestored({ context: `client-trip:${mode}` });
  const [driverName, setDriverName] = useState<string | null>(null);
  const [showReceipt, setShowReceipt] = useState(false);

  const meta = (ride?.metadata ?? {}) as Record<string, unknown>;
  const showPickupConfirm =
    !!ride && ride.status === "pending" && meta.phase === "arrived" && !!ride.driver_id;
  const pickupCode = (meta.pickup_code as string | undefined) ?? null;

  useEffect(() => {
    if (ride?.status === "completed") setShowReceipt(true);
  }, [ride?.status]);

  useEffect(() => {
    try {
      Analytics.track("ride.trust_message_viewed" as any, {
        metadata: { surface: "realtime_trip", mode },
      });
    } catch {}
  }, [mode]);

  useEffect(() => {
    if (!ride?.driver_id) return;
    supabase.from("profiles").select("full_name, display_name")
      .eq("user_id", ride.driver_id).maybeSingle()
      .then(({ data }) => {
        setDriverName(data?.display_name ?? data?.full_name ?? null);
      });
  }, [ride?.driver_id]);

  const releaseHold = async (reason: string) => {
    if (!holdId || settled.current) return;
    settled.current = true;
    try { await supabase.rpc("wallet_release", { p_hold_id: holdId, p_reason: reason }); } catch {}
  };

  const handleCallDriver = async (driverId: string) => {
    const { data } = await supabase
      .from("profiles")
      .select("phone, full_name")
      .eq("user_id", driverId)
      .maybeSingle();
    if (data?.phone) {
      window.location.href = `tel:${data.phone}`;
    } else {
      toast({ title: "Numéro indisponible", description: "Contactez le support si besoin." });
    }
  };

  const handleCancel = async () => {
    await releaseHold("Course annulée par le client");
    toast({ title: "Course annulée", description: "Vos fonds réservés ont été libérés." });
    (onCancel ?? onClose)();
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      {showReceipt && ride && (
        <ClientTripReceipt
          rideId={rideId}
          fareGnf={ride.fare_gnf ?? 0}
          driverName={driverName}
          paymentLabel="Espèces"
          onClose={onClose}
        />
      )}
      <div className="gradient-primary px-4 py-3 flex items-center justify-between shrink-0">
        <button
          type="button"
          onClick={onClose}
          aria-label="Fermer"
          className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition"
        >
          <X className="w-5 h-5 text-primary-foreground" />
        </button>
        <div className="flex items-center gap-2 min-w-0">
          <span className="text-primary-foreground text-sm font-semibold truncate">{TITLES[mode]}</span>
          {ride && <RidePhaseChip phase={deriveRidePhase(ride)} size="sm" />}
        </div>
        <div className="w-9" />
      </div>
      <div className="px-4 py-2 bg-card/60 border-b border-border/60">
        <TrustCues cues={["live", "choppay", "support"]} compact className="justify-center" />
      </div>

      <div className="flex-1 min-h-0">
        <div className="relative h-full">
          <ActiveTripMap
            rideId={rideId}
            driverName={driverName}
            onCallDriver={handleCallDriver}
            onCancel={handleCancel}
            onClose={onClose}
            hideBottomSheet={showPickupConfirm}
          />
          {showPickupConfirm && (
            <PickupConfirmCard
              rideId={rideId}
              driverName={driverName}
              pickupCode={pickupCode}
              vehicleLabel={mode === "toktok" ? "TokTok" : mode === "moto" ? "Moto" : undefined}
              onCallDriver={ride?.driver_id ? () => handleCallDriver(ride.driver_id!) : undefined}
            />
          )}
        </div>
      </div>
    </motion.div>
  );
}