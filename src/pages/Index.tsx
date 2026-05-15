import { useEffect, useRef, useState } from "react";
import { formatGNF } from "@/lib/format";
import { AnimatePresence } from "framer-motion";
import { UserHome } from "@/components/views/UserHome";
import { DriverHome } from "@/components/views/DriverHome";
import { RideBooking } from "@/components/ride/RideBooking";
import { LiveTracking, type TrackingMode } from "@/components/tracking/LiveTracking";
import { RealtimeTripScreen } from "@/components/trip/RealtimeTripScreen";
import { QrScanner } from "@/components/scanner/QrScanner";
import { toast } from "@/hooks/use-toast";
import { FoodView } from "@/components/views/FoodView";
import { MarketView } from "@/components/views/MarketView";
import { WalletView } from "@/components/views/WalletView";
import { ProfileView } from "@/components/views/ProfileView";
import { OrdersView } from "@/components/views/OrdersView";
import { DriverOrdersView } from "@/components/views/DriverOrdersView";
import { DriverEarningsView } from "@/components/views/DriverEarningsView";
import { BottomNav } from "@/components/ui/BottomNav";
import { supabase } from "@/integrations/supabase/client";
import { Seo } from "@/components/Seo";
import { useAuthGuard } from "@/hooks/useAuthGuard";
import { useAuth } from "@/contexts/AuthContext";
import { notifications as notif } from "@/lib/notifications";
import { useNavigate } from "react-router-dom";
import { DriverSessionProvider } from "@/contexts/DriverSessionContext";
import { DriverRideAlertBanner } from "@/components/driver/DriverRideAlertBanner";
import { useDriverSession } from "@/contexts/DriverSessionContext";
import { DriverOfferDebugPanel } from "@/components/driver/DriverOfferDebugPanel";
import { ClientOnboarding, ONBOARDING_DONE_KEY, ONBOARDING_REPLAY_EVENT } from "@/components/onboarding/ClientOnboarding";
import {
  DriverOnboarding,
  DRIVER_ONBOARDING_DONE_KEY,
  DRIVER_ONBOARDING_REPLAY_EVENT,
} from "@/components/onboarding/DriverOnboarding";
import { useDriverProfile } from "@/hooks/useDriverProfile";

export type RideType = "moto" | "toktok" | null;
export type ActiveView = "home" | "food" | "market" | "wallet" | "profile" | "orders";

/**
 * Renders the global driver ride-alert banner. Lives inside the provider so it
 * can read the current offer and surface it from any tab.
 */
function DriverGlobalAlert({ activeTab, onView }: { activeTab: string; onView: () => void }) {
  const { queue, activeTrip, activeRideId } = useDriverSession();
  if (queue.length === 0 || activeTrip || activeRideId) return null;
  // Courses tab already shows the floating island popup — avoid duplicate alerts.
  if (activeTab === "orders") return null;
  return <DriverRideAlertBanner activeTab={activeTab} onView={onView} />;
}

/**
 * First-entry driver onboarding gate. Lives inside DriverSessionProvider so it
 * can suppress itself during any active operation (offer popup, accepted trip,
 * QR/pickup waiting state). Sandbox/debug flows skip onboarding entirely.
 */
function DriverOnboardingGate() {
  const { user } = useAuth();
  const { profile } = useDriverProfile();
  const { queue, current, activeTrip, activeRideId } = useDriverSession();
  const [show, setShow] = useState(false);

  const sandboxOn = typeof window !== "undefined" && (
    /[?&]sandbox=1/.test(window.location.search) ||
    /[?&]debug=1/.test(window.location.search)
  );

  useEffect(() => {
    if (typeof window === "undefined" || !user || !profile) return;
    if (profile.status !== "approved") return;
    if (sandboxOn) return;
    const key = `${DRIVER_ONBOARDING_DONE_KEY}:${user.id}`;
    if (localStorage.getItem(key) === "1") return;
    setShow(true);
  }, [user?.id, profile?.status, sandboxOn]);

  useEffect(() => {
    const handler = () => setShow(true);
    window.addEventListener(DRIVER_ONBOARDING_REPLAY_EVENT, handler);
    return () => window.removeEventListener(DRIVER_ONBOARDING_REPLAY_EVENT, handler);
  }, []);

  // Never interrupt active driver operations.
  const busy = !!activeTrip || !!activeRideId || !!current || queue.length > 0;
  if (!show || busy) return null;

  const finish = () => {
    setShow(false);
    if (user) {
      try { localStorage.setItem(`${DRIVER_ONBOARDING_DONE_KEY}:${user.id}`, "1"); } catch { /* noop */ }
    }
  };

  return (
    <AnimatePresence>
      <DriverOnboarding key="driver-onboarding" onDone={finish} />
    </AnimatePresence>
  );
}

const Index = () => {
  // Always start in client mode; we only flip to driver once `user` is loaded
  // and we've confirmed the demo driver account or an explicit flag.
  // (Initialising from sessionStorage before auth resolves caused
  // DriverHome to render outside a ready provider on first paint.)
  const [isDriverMode, setIsDriverMode] = useState<boolean>(false);
  const [activeTab, setActiveTab] = useState("home");
  const [activeView, setActiveView] = useState<ActiveView>("home");
  const [bookingRide, setBookingRide] = useState<RideType>(null);
  const [bookingDestination, setBookingDestination] = useState<string | undefined>(undefined);
  const [activeTrip, setActiveTrip] = useState<{
    mode: TrackingMode;
    pickupCoords: [number, number];
    destCoords?: [number, number];
    fare: number;
    holdId?: string | null;
    rideId?: string | null;
  } | null>(null);
  const [showScanner, setShowScanner] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const { requireAuth } = useAuthGuard();
  const { roles, user } = useAuth();
  const isDriver = roles.includes("driver");
  const navigate = useNavigate();
  // Demo mode flavours:
  // - linked E2E (sandbox): explicit `?demo=linked` — hands the ride to the
  //   real demo driver account. Used for two-account presentations.
  // - walkthrough (default for demo client): self-guided clickthrough that
  //   never waits on a real driver. Used for solo presentations.
  const isLinkedDemo = typeof window !== "undefined"
    && /[?&]demo=linked\b/.test(window.location.search);
  const isDemoAny = isLinkedDemo;
  // One-shot guard: only auto-enter driver mode the first time we see this
  // signed-in demo driver. After that, manual toggles win.
  const autoModeAppliedRef = useRef(false);

  // First-login client onboarding: show once per user. Replay via Profile menu.
  useEffect(() => {
    if (typeof window === "undefined") return;
    if (isDriverMode) return;
    // Show onboarding to first-time visitors as well as first-time signed-in users.
    const key = `${ONBOARDING_DONE_KEY}:${user?.id ?? "guest"}`;
    if (localStorage.getItem(key) !== "1") setShowOnboarding(true);
  }, [user?.id, isDriverMode]);

  useEffect(() => {
    const handler = () => setShowOnboarding(true);
    window.addEventListener(ONBOARDING_REPLAY_EVENT, handler);
    return () => window.removeEventListener(ONBOARDING_REPLAY_EVENT, handler);
  }, []);

  const finishOnboarding = () => {
    setShowOnboarding(false);
    if (typeof window !== "undefined") {
      try {
        localStorage.setItem(`${ONBOARDING_DONE_KEY}:${user?.id ?? "guest"}`, "1");
      } catch { /* noop */ }
    }
  };

  // Logout: clear persisted mode and reset.
  useEffect(() => {
    if (typeof window === "undefined") return;
    if (!user) {
      sessionStorage.removeItem("cc_driver_mode");
      autoModeAppliedRef.current = false;
      if (isDriverMode) setIsDriverMode(false);
    }
  }, [user?.id, isDriverMode]);

  // Persist mode changes once a user is signed in.
  useEffect(() => {
    if (typeof window === "undefined" || !user) return;
    sessionStorage.setItem("cc_driver_mode", isDriverMode ? "1" : "0");
  }, [user?.id, isDriverMode]);

  // After auth resolves, decide initial mode for this session: auto-enter
  // driver mode for the demo driver account or explicit `?demo=driver`,
  // otherwise restore whatever mode was persisted earlier this session.
  // Runs once per signed-in session — manual toggles afterwards win.
  useEffect(() => {
    if (!user || autoModeAppliedRef.current) return;
    autoModeAppliedRef.current = true;
    const email = (user.email ?? "").toLowerCase();
    const isDemoDriverAccount = email === "demo.driver@chopchop.gn";
    const isExplicitDriverDemo =
      typeof window !== "undefined" && /[?&]demo=driver\b/.test(window.location.search);
    if (isDemoDriverAccount || isExplicitDriverDemo) {
      setIsDriverMode(true);
      setActiveTab("home");
      setActiveView("home");
      return;
    }
    if (typeof window !== "undefined" && sessionStorage.getItem("cc_driver_mode") === "1") {
      setIsDriverMode(true);
    }
  }, [user?.id, user?.email]);

  // Rides the user has actively dismissed this session — never re-restore them.
  const dismissedRidesRef = useRef<Set<string>>(new Set());
  // Only attempt the auto-restore once per mount; closing the trip should not
  // immediately re-open the same ride from the DB.
  const restoreAttemptedRef = useRef(false);

  // Restore an in-flight client ride after refresh / reconnect / reopen.
  // Source of truth is the rides table. We only restore RECENT, in-progress
  // rides — orphan pending rides (no driver assigned, older than 30 min) are
  // ignored so they never trap the user on the tracking screen.
  useEffect(() => {
    if (!user || isDriverMode || activeTrip || restoreAttemptedRef.current) return;
    // Demo mode = calm guided showroom: never auto-restore an in-flight ride
    // on the client. The user must intentionally tap a dashboard action.
    if (isDemoAny) { restoreAttemptedRef.current = true; return; }
    restoreAttemptedRef.current = true;
    let cancelled = false;
    (async () => {
      const cutoffRecent = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const { data: ride } = await supabase
        .from("rides")
        .select("id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,fare_gnf,hold_tx_id,status,driver_id,created_at")
        .eq("client_id", user.id)
        .in("status", ["pending", "in_progress"])
        .gte("created_at", cutoffRecent)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (cancelled || !ride) return;
      // Skip orphan pending rides with no driver assigned for >30 min.
      const ageMs = Date.now() - new Date(ride.created_at as string).getTime();
      if (ride.status === "pending" && !ride.driver_id && ageMs > 30 * 60 * 1000) return;
      if (dismissedRidesRef.current.has(ride.id)) return;
      setActiveTrip({
        mode: ride.mode as TrackingMode,
        pickupCoords: [Number(ride.pickup_lat), Number(ride.pickup_lng)],
        destCoords: ride.dest_lat != null && ride.dest_lng != null
          ? [Number(ride.dest_lat), Number(ride.dest_lng)]
          : undefined,
        fare: Number(ride.fare_gnf ?? 0),
        holdId: ride.hold_tx_id ?? null,
        rideId: ride.id,
      });
    })();
    return () => { cancelled = true; };
  }, [user?.id, isDriverMode, activeTrip]);

  const closeActiveTrip = async (alsoCancel: boolean) => {
    const trip = activeTrip;
    if (trip?.rideId) {
      dismissedRidesRef.current.add(trip.rideId);
      // Linked demo: never cancel server-side on close. The demo driver still
      // needs to be able to accept the same ride_id after the operator
      // switches accounts. Just dismiss locally for this session.
      if (alsoCancel && isLinkedDemo) {
        try {
          const { data: row } = await supabase
            .from("rides")
            .select("metadata,status")
            .eq("id", trip.rideId)
            .maybeSingle();
          const meta = (row?.metadata ?? {}) as { linked_demo?: boolean };
          const stillLive = row?.status === "pending" || row?.status === "in_progress";
          if (meta.linked_demo === true && stillLive) {
            toast({
              title: "Démo masquée",
              description: "La course reste active pour le chauffeur.",
            });
            setActiveTrip(null);
            setActiveView("orders");
            setActiveTab("orders");
            return;
          }
        } catch { /* fall through to default cancel */ }
      }
      // If the user closes a still-pending (un-matched) ride, cancel it
      // server-side so it does not stay around as an orphan.
      if (alsoCancel) {
        try { await supabase.rpc("ride_cancel", { p_ride_id: trip.rideId, p_reason: "client_dismissed" } as never); } catch { /* noop */ }
      }
    }
    setActiveTrip(null);
    setActiveView("orders");
    setActiveTab("orders");
  };

  const enableDriverMode = () => {
    if (!requireAuth()) return;
    if (!isDriver) {
      toast({
        title: "Devenir chauffeur",
        description: "Postulez pour commencer à conduire avec CHOP CHOP.",
      });
      navigate("/driver/apply");
      return;
    }
    setIsDriverMode(true);
  };

  const handleAction = (action: string, params?: { destination?: string }) => {
    // Public exploration: ride booking, food and market browsing are allowed
    // without an account. Signup is enforced later at commitment points
    // (real wallet hold / real ride creation).
    const publicActions = new Set(["market", "food", "moto", "toktok", "parcel", "scan", "support"]);
    if (!publicActions.has(action) && !requireAuth()) return;
    switch (action) {
      case "moto":
        setBookingDestination(params?.destination);
        setBookingRide("moto");
        break;
      case "toktok":
        setBookingDestination(params?.destination);
        setBookingRide("toktok");
        break;
      case "food":
        setActiveView("food");
        break;
      case "market":
        setActiveView("market");
        break;
      case "send":
      case "wallet":
        setActiveView("wallet");
        setActiveTab("wallet");
        break;
      case "parcel":
        // Parcel delivery shares the moto coursier flow for now.
        setBookingDestination(params?.destination);
        setBookingRide("moto");
        break;
      case "scan":
        setShowScanner(true);
        break;
      case "orders":
        setActiveView("orders");
        setActiveTab("orders");
        break;
      case "support":
        navigate("/help");
        break;
      default:
        break;
    }
  };

  const handleTabChange = (tab: string) => {
    // Home tab is public; every other tab requires an account.
    if (tab !== "home" && !requireAuth()) return;
    setActiveTab(tab);
    if (tab === "home") setActiveView("home");
    if (tab === "orders") setActiveView("orders");
    if (tab === "wallet") setActiveView("wallet");
    if (tab === "profile") setActiveView("profile");
  };

  const handleBackToHome = () => {
    setActiveView("home");
    setActiveTab("home");
  };

  const renderUserView = () => {
    switch (activeView) {
      case "food":
        return <FoodView onBack={handleBackToHome} />;
      case "market":
        return <MarketView onBack={handleBackToHome} />;
      case "wallet":
        return <WalletView />;
      case "profile":
        return (
          <ProfileView
            isDriverMode={isDriverMode}
            onToggleDriverMode={() => setIsDriverMode(!isDriverMode)}
          />
        );
      case "orders":
        return <OrdersView />;
      default:
        return (
          <UserHome
            onActionClick={handleAction}
            onToggleDriverMode={enableDriverMode}
          />
        );
    }
  };

  const renderDriverView = () => {
    switch (activeTab) {
      case "orders":
        return <DriverOrdersView />;
      case "wallet":
        return <DriverEarningsView />;
      case "profile":
        return (
          <ProfileView
            isDriverMode={isDriverMode}
            onToggleDriverMode={() => setIsDriverMode(!isDriverMode)}
          />
        );
      default:
        return <DriverHome onToggleDriverMode={() => setIsDriverMode(false)} />;
    }
  };

  return (
    <div className="min-h-screen bg-background pb-20">
      <Seo
        title="CHOP CHOP — Transport, livraison et paiements en Guinée"
        description="La super-app guinéenne : moto et TokTok, livraison de repas, marché en ligne et transferts d'argent en GNF. Tout, partout, pour tous."
        canonical="/"
      />
      <h1 className="sr-only">CHOP CHOP — Vos services de transport, livraison et paiements en Guinée</h1>
      <AnimatePresence mode="wait">
        {bookingRide && (
          <RideBooking
            type={bookingRide}
            initialDestination={bookingDestination}
            onClose={() => {
              setBookingRide(null);
              setBookingDestination(undefined);
            }}
            onBook={async (trip) => {
              const { data: sess } = await supabase.auth.getSession();
              if (!sess.session) {
                toast({ title: "Connexion requise", description: "Connectez-vous pour réserver." });
                return;
              }
              const holdAmount = Math.ceil(trip.fare * 1.1);
              const { data, error } = await supabase.rpc("wallet_hold", {
                p_amount_gnf: holdAmount,
                p_reference: null,
                p_description: `Réservation ${bookingRide}`,
              });
              if (error) {
                toast({ title: "Solde insuffisant", description: error.message });
                return;
              }
              const holdId = (data as { id: string }).id;
              const { data: ride, error: rideErr } = await supabase.rpc("ride_create", {
                p_mode: bookingRide,
                p_pickup_lat: trip.pickupCoords[0],
                p_pickup_lng: trip.pickupCoords[1],
                p_dest_lat: trip.destCoords?.[0] ?? null,
                p_dest_lng: trip.destCoords?.[1] ?? null,
                p_fare_gnf: Math.round(trip.fare),
                p_hold_tx_id: holdId,
                p_driver_id: null,
              });
              if (rideErr) {
                await supabase.rpc("wallet_release", { p_hold_id: holdId, p_reason: "Création course échouée" });
                toast({ title: "Erreur", description: rideErr.message });
                return;
              }
              const newRideId = (ride as { id: string }).id;
              // Linked demo (sandbox E2E): hand the ride to the demo driver
              // as a real offer. Walkthrough demo never links.
              if (isLinkedDemo) {
                try {
                  await supabase.rpc("demo_link_ride" as never, { p_ride_id: newRideId } as never);
                } catch (e) {
                  // eslint-disable-next-line no-console
                  console.warn("[demo_link_ride] failed", e);
                }
              }
              setActiveTrip({ mode: bookingRide, ...trip, holdId, rideId: newRideId });
              setBookingRide(null);
              setBookingDestination(undefined);
              notif.push({
                kind: "ride",
                title: "Course confirmée",
                body: `Votre ${bookingRide?.toUpperCase()} est en route. Fonds réservés : ${formatGNF(holdAmount)}.`,
              });
              toast({
                title: "Fonds réservés",
                description: `${formatGNF(holdAmount)} bloqués jusqu'à la fin de course.`,
              });
            }}
          />
        )}
        {activeTrip && (
          (typeof window !== "undefined" &&
            (localStorage.getItem("cc_realtime_trip") === "1" ||
              /[?&]trip=v2/.test(window.location.search) ||
              /[?&]demo=1/.test(window.location.search) ||
              isLinkedDemo)) && activeTrip.rideId
          ? (
            <RealtimeTripScreen
              key={`v2-${activeTrip.rideId}`}
              rideId={activeTrip.rideId}
              mode={activeTrip.mode as "moto" | "toktok"}
              holdId={activeTrip.holdId}
              onClose={() => closeActiveTrip(true)}
            />
          )
          : <LiveTracking
            mode={activeTrip.mode}
            pickupCoords={activeTrip.pickupCoords}
            destCoords={activeTrip.destCoords}
            fare={activeTrip.fare}
            holdId={activeTrip.holdId}
            rideId={activeTrip.rideId}
            onClose={() => closeActiveTrip(true)}
          />
        )}
      </AnimatePresence>

      {!bookingRide && !activeTrip && (
        isDriverMode ? (
          <DriverSessionProvider>
            {renderDriverView()}
            <DriverGlobalAlert
              activeTab={activeTab}
              onView={() => {
                setActiveTab("orders");
                setActiveView("orders");
              }}
            />
            <DriverOfferDebugPanel activeTab={activeTab} />
            <DriverOnboardingGate />
            <BottomNav
              activeTab={activeTab}
              onTabChange={handleTabChange}
              isDriverMode={isDriverMode}
              onScanClick={() => handleAction("scan")}
            />
          </DriverSessionProvider>
        ) : (
          <>
            {renderUserView()}
            <BottomNav
              activeTab={activeTab}
              onTabChange={handleTabChange}
              isDriverMode={isDriverMode}
              onScanClick={() => handleAction("scan")}
            />
          </>
        )
      )}

      {showScanner && (
        <QrScanner
          title="Scanner un QR CHOP CHOP"
          subtitle="Course, paiement ou code marchand"
          onClose={() => setShowScanner(false)}
          onResult={(text) => {
            setShowScanner(false);
            toast({ title: "Code scanné", description: text });
          }}
        />
      )}

      <AnimatePresence>
        {showOnboarding && !isDriverMode && (
          <ClientOnboarding key="client-onboarding" onDone={finishOnboarding} />
        )}
      </AnimatePresence>
    </div>
  );
};

export default Index;
