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
import { useAuth } from "@/contexts/AuthContext";

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
  currentExpiresAt: string | null;
  showCurrent: () => void;
  accept: (id: string) => Promise<void>;
  decline: (id: string) => Promise<void>;
  activeTrip: IncomingRequest | null;
  activeRideId: string | null;
  latestOffer: RideOffer | null;
  realtimeStatus: string;
  blockingReason: string;
  createDebugOfferForCurrentDriver: () => Promise<void>;
}

const DriverSessionContext = createContext<DriverSessionValue | null>(null);

export function useDriverSession() {
  const ctx = useContext(DriverSessionContext);
  if (!ctx) throw new Error("useDriverSession must be used inside DriverSessionProvider");
  return ctx;
}

export function DriverSessionProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const { profile, loading: profileLoading, refetch } = useDriverProfile();
  const isDemoDriver = (user?.email ?? "").toLowerCase() === "demo.driver@chopchop.gn";
  const demoModeOn = typeof window !== "undefined" && (
    import.meta.env.DEV ||
    /[?&](demo|debug)=1/.test(window.location.search) ||
    window.location.hostname.includes("lovable")
  );
  const demoAutoOffer = isDemoDriver && demoModeOn;
  const [isOnline, setIsOnline] = useState(false);
  const [toggling, setToggling] = useState(false);
  const [current, setCurrent] = useState<IncomingRequest | null>(null);
  const [activeTrip, setActiveTrip] = useState<IncomingRequest | null>(null);
  const [activeRideId, setActiveRideId] = useState<string | null>(null);
  const { offers, latestOffer, realtimeStatus, refetch: refetchOffers } = useIncomingOffers(isOnline);
  const queue = offers.map(offerToRequest);
  const currentExpiresAt = current
    ? offers.find((o) => o.id === current.id)?.expires_at ?? null
    : offers[0]?.expires_at ?? null;

  useDriverPresence({ enabled: isOnline, onTrip: !!activeTrip });

  useEffect(() => {
    if (profile) setIsOnline(profile.presence !== "offline");
  }, [profile?.presence]);

  // If the driver refreshes while already on a ride, rebuild local trip state
  // from the database so the navigation screen is available again.
  useEffect(() => {
    if (!user || profile?.presence !== "on_trip" || activeTrip || activeRideId) return;

    let cancelled = false;
    const restoreActiveRide = async () => {
      const { data: ride } = await supabase
        .from("rides")
        .select("id,fare_gnf")
        .eq("driver_id", user.id)
        .not("status", "in", "(completed,cancelled)")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!ride || cancelled) return;

      const { data: offer } = await supabase
        .from("ride_offers")
        .select("id,pickup_zone,destination_zone,estimated_fare_gnf,estimated_earning_gnf,distance_to_pickup_m")
        .eq("ride_id", ride.id)
        .eq("driver_id", user.id)
        .order("sent_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (cancelled) return;
      setActiveRideId(ride.id);
      setActiveTrip(offerToRequest({
        id: offer?.id ?? ride.id,
        ride_id: ride.id,
        pickup_zone: offer?.pickup_zone ?? "Point de départ",
        destination_zone: offer?.destination_zone ?? "Destination",
        estimated_fare_gnf: offer?.estimated_fare_gnf ?? ride.fare_gnf ?? 0,
        estimated_earning_gnf: offer?.estimated_earning_gnf ?? ride.fare_gnf ?? 0,
        distance_to_pickup_m: offer?.distance_to_pickup_m ?? null,
        expires_at: new Date(Date.now() + 30_000).toISOString(),
        status: "accepted",
      }));
    };

    restoreActiveRide();
    return () => { cancelled = true; };
  }, [user?.id, profile?.presence, activeTrip, activeRideId]);

  const cashOverLimit = !!profile && profile.cash_debt_gnf >= profile.debt_limit_gnf;
  const blockingReason = activeTrip || activeRideId
    ? "course_active"
    : !profile
      ? "profil_chauffeur_introuvable"
      : profile.status !== "approved"
        ? `statut_chauffeur_${profile.status}`
        : !isOnline
          ? `presence_${profile.presence}`
          : queue.length === 0
            ? latestOffer
              ? latestOffer.status !== "pending"
                ? `derniere_offre_${latestOffer.status}`
                : new Date(latestOffer.expires_at).getTime() <= Date.now()
                  ? "derniere_offre_expiree"
                  : "aucune_offre_visible"
              : "aucune_offre"
            : current
              ? "visible"
              : "en_attente_affichage";

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

  // Drop the current offer if it expired or was cancelled server-side.
  useEffect(() => {
    if (!current) return;
    const stillThere = offers.some((o) => o.id === current.id);
    if (!stillThere) setCurrent(null);
  }, [offers, current?.id]);

  const accept = useCallback(async (id: string) => {
    const accepted = current?.id === id ? current : queue.find((request) => request.id === id) ?? null;
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
  }, [current, queue, refetchOffers]);

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

  // Demo-only: auto-generate ride offer popups so the demo driver flow
  // is reliably testable end-to-end without manual admin action.
  useEffect(() => {
    if (!demoAutoOffer) return;
    if (!isOnline) return;
    if (activeTrip || activeRideId) return;
    // Only generate if no pending offer (queue empty) and no visible popup.
    if (queue.length > 0 || current) return;
    // If the latest offer is still pending or only just terminal, wait briefly.
    const cooldownMs = latestOffer && latestOffer.status !== "pending"
      ? 4000
      : 6000 + Math.floor(Math.random() * 4000); // 6–10s

    let cancelled = false;
    const timer = window.setTimeout(async () => {
      if (cancelled) return;
      try {
        const { error } = await supabase.rpc("debug_create_offer_for_current_driver" as never);
        if (error) {
          // eslint-disable-next-line no-console
          console.warn("[demo-auto-offer] failed", error);
          return;
        }
        await refetchOffers();
      } catch (e) {
        // eslint-disable-next-line no-console
        console.warn("[demo-auto-offer] exception", e);
      }
    }, cooldownMs);

    return () => { cancelled = true; window.clearTimeout(timer); };
  }, [demoAutoOffer, isOnline, activeTrip, activeRideId, queue.length, current?.id, latestOffer?.id, latestOffer?.status, refetchOffers]);

  const createDebugOfferForCurrentDriver = useCallback(async () => {
    setActiveTrip(null);
    setActiveRideId(null);
    setCurrent(null);
    const { data, error } = await supabase.rpc("debug_create_offer_for_current_driver" as never);
    if (error) {
      toast.error("Création offre debug échouée", { description: error.message });
      return;
    }
    const offerId = (data as { offer_id?: string } | null)?.offer_id;
    // eslint-disable-next-line no-console
    console.log("[driver_offer_debug] created offer", offerId, data);
    toast.success("Offre test créée pour ce chauffeur", {
      description: offerId ? `Offer ${offerId.slice(0, 8)} • expire dans 60 s` : undefined,
    });
    setActiveTrip(null);
    setActiveRideId(null);
    setCurrent(null);
    setIsOnline(true);
    refetch();
    await refetchOffers();
  }, [refetch, refetchOffers]);

  const value: DriverSessionValue = {
    profile, profileLoading, refetchProfile: refetch,
    isOnline, toggling, togglePresence, cashOverLimit,
    queue, current, currentExpiresAt, showCurrent, accept, decline,
    activeTrip, activeRideId,
    latestOffer, realtimeStatus, blockingReason, createDebugOfferForCurrentDriver,
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