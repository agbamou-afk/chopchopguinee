import { motion } from "framer-motion";
import { X } from "lucide-react";
import { ActiveTripMap } from "./ActiveTripMap";
import { ClientTripReceipt } from "./ClientTripReceipt";
import { useRideRealtime } from "@/hooks/useRideRealtime";
import { useRideLifecycleNotifications } from "@/hooks/useRideLifecycleNotifications";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { useEffect, useRef, useState } from "react";

interface Props {
  rideId: string;
  mode: "moto" | "toktok" | "food";
  /** Wallet hold to release if the user cancels before pickup. */
  holdId?: string | null;
  onClose: () => void;
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
export function RealtimeTripScreen({ rideId, mode, holdId, onClose }: Props) {
  const settled = useRef(false);
  const { ride } = useRideRealtime(rideId);
  useRideLifecycleNotifications(ride, "client");
  const [driverName, setDriverName] = useState<string | null>(null);
  const [showReceipt, setShowReceipt] = useState(false);

  useEffect(() => {
    if (ride?.status === "completed") setShowReceipt(true);
  }, [ride?.status]);

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
    onClose();
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
        <div className="text-primary-foreground text-sm font-semibold">{TITLES[mode]}</div>
        <div className="w-9" />
      </div>

      <div className="flex-1 min-h-0">
        <ActiveTripMap
          rideId={rideId}
          onCallDriver={handleCallDriver}
          onCancel={handleCancel}
          onClose={onClose}
        />
      </div>
    </motion.div>
  );
}