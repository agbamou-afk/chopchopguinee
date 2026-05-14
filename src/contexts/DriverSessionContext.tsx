import { createContext, useContext, useEffect, useState, useCallback, ReactNode } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useDriverProfile } from "@/hooks/useDriverProfile";
import { useDriverPresence } from "@/hooks/useDriverPresence";
import { useIncomingOffers, type RideOffer } from "@/hooks/useIncomingOffers";
import type { IncomingRequest } from "@/components/driver/IncomingRequestPopup";
import { DriverActiveTrip } from "@/components/driver/DriverActiveTrip";
import { DriverTripView } from "@/components/driver/DriverTripView";
import { Analytics } from "@/lib/analytics/AnalyticsService";

function offerToRequest(o: RideOffer): IncomingRequest {
  const distKm = o.distance_to_pickup_m ? (o.distance_to_pickup_m / 1000).toFixed(1) : "—";
  return {
    id: o.id,
    type: "ride",
    pickup: o.pickup_zone || "Point de départ",
    destination: o.destination_zone || "Destination",
    customerName: "Client",
    customerRating: 5,
    estimatedPrice: o.estimated_earning_gnf ?? o.estimated_fare_gnf ?? 0,
    distance: distKm === "—" ? "—" : `${distKm} km`,
    eta: "—",
  };
}

interface DriverSessionValue {
  profile: ReturnType<typeof useDriverProfile>["profile"];
  profileLoading: boolean;
  refetchProfile: () => void;
  isOnline: boolean;
  toggling: boolean;
  togglePresence: () => Promise<void>;
  cashOverLimit: boolean;
  queue: IncomingRequest[];
  current: IncomingRequest | null;
  showCurrent: () => void;
  accept: (id: string) => Promise<void>;
  decline: (id: string) => Promise<void>;
  activeTrip: IncomingRequest | null;
  activeRideId: string | null;
}

const DriverSessionContext = createContext<DriverSessionValue | null>(null);

export function useDriverSession() {
  const ctx = useContext(DriverSessionContext);
  if (!ctx) throw new Error("useDriverSession must be used inside DriverSessionProvider");
  return ctx;
}

export function DriverSessionProvider({ children }: { children: ReactNode }) {
  const { profile, loading: profileLoading, refetch } = useDriverProfile();
  const [isOnline, setIsOnline] = useState(false);
  const [toggling, setToggling] = useState(false);
  const [current, setCurrent] = useState<IncomingRequest | null>(null);
  const [activeTrip, setActiveTrip] = useState<IncomingRequest | null>(null);
  const [activeRideId, setActiveRideId] = useState<string | null>(null);
  const { offers, refetch: refetchOffers } = useIncomingOffers(isOnline);
  const queue = offers.map(offerToRequest);

  useDriverPresence({ enabled: isOnline, onTrip: !!activeTrip });

  useEffect(() => {
    if (profile) setIsOnline(profile.presence !== "offline");
  }, [profile?.presence]);

  const cashOverLimit = !!profile && profile.cash_debt_gnf >= profile.debt_limit_gnf;

  const togglePresence = useCallback(async () => {
    if (!profile || toggling) return;
    const next = isOnline ? "offline" : "online";
    if (next === "online" && cashOverLimit) {
      toast.error("Limite de cash atteinte. Réglez votre commission pour repasser en ligne.");
      Analytics.track("driver.cash.over_limit", { metadata: { cash_debt_gnf: profile.cash_debt_gnf } });
      return;
    }
    setToggling(true);
    const { error } = await supabase.rpc("driver_set_status", { p_status: next });
    setToggling(false);
    if (error) {
      toast.error(error.message || "Impossible de changer le statut.");
      return;
    }
    setIsOnline(next === "online");
    refetch();
    Analytics.track(next === "online" ? "driver.online" : "driver.offline", {
      metadata: { vehicle_type: profile.vehicle_type },
    });
    toast.success(next === "online" ? "Vous êtes en ligne." : "Vous êtes hors ligne.");
  }, [profile, toggling, isOnline, cashOverLimit, refetch]);

  // Auto-pop next offer when online and idle
  useEffect(() => {
    if (!isOnline || current || activeTrip || queue.length === 0) return;
    setCurrent(queue[0]);
  }, [isOnline, current, activeTrip, queue]);

  const accept = useCallback(async (id: string) => {
    const accepted = current;
    setCurrent(null);
    const { data, error } = await supabase.rpc("driver_offer_accept", { p_offer_id: id });
    if (error) {
      toast.error(error.message || "Impossible d'accepter cette course.");
      refetchOffers();
      return;
    }
    if (accepted) {
      setActiveTrip(accepted);
      const rideId = (data as { ride_id?: string } | null)?.ride_id;
      if (rideId) setActiveRideId(rideId);
      toast.success("Course acceptée — direction le client.");
    }
    Analytics.track("driver.ride.accepted", { metadata: { offer_id: id, fare_gnf: accepted?.estimatedPrice } });
    refetchOffers();
  }, [current, refetchOffers]);

  const decline = useCallback(async (id: string) => {
    setCurrent(null);
    const { error } = await supabase.rpc("driver_offer_decline", { p_offer_id: id });
    if (error) toast.error(error.message);
    else toast.info("Course refusée");
    Analytics.track("driver.ride.declined", { metadata: { offer_id: id } });
    refetchOffers();
  }, [refetchOffers]);

  const showCurrent = useCallback(() => {
    if (queue.length === 0) {
      toast.info("Aucune demande en attente");
      return;
    }
    setCurrent(queue[0]);
  }, [queue]);

  const closeTrip = () => { setActiveTrip(null); setActiveRideId(null); };

  const value: DriverSessionValue = {
    profile, profileLoading, refetchProfile: refetch,
    isOnline, toggling, togglePresence, cashOverLimit,
    queue, current, showCurrent, accept, decline,
    activeTrip, activeRideId,
  };

  // Always prefer the in-app navigation screen (DriverActiveTrip) when we
  // have a real ride id. Fall back to the legacy preview screen only when
  // the offer didn't return one (defensive — should not happen in prod).
  return (
    <DriverSessionContext.Provider value={value}>
      {children}
      {activeTrip && (
        activeRideId
          ? <DriverActiveTrip rideId={activeRideId} onClose={closeTrip} />
          : <DriverTripView request={activeTrip} onClose={closeTrip} />
      )}
    </DriverSessionContext.Provider>
  );
}