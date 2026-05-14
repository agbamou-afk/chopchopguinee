import { useState } from "react";
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

export type RideType = "moto" | "toktok" | null;
export type ActiveView = "home" | "food" | "market" | "wallet" | "profile" | "orders";

/**
 * Renders the global driver ride-alert banner. Lives inside the provider so it
 * can read the current offer and surface it from any tab.
 */
function DriverGlobalAlert({ activeTab, onView }: { activeTab: string; onView: () => void }) {
  const { queue, activeTrip, activeRideId } = useDriverSession();
  if (queue.length === 0 || activeTrip || activeRideId) return null;
  return <DriverRideAlertBanner activeTab={activeTab} onView={onView} />;
}

const Index = () => {
  const [isDriverMode, setIsDriverMode] = useState(false);
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
  const { requireAuth } = useAuthGuard();
  const { roles } = useAuth();
  const isDriver = roles.includes("driver");
  const navigate = useNavigate();

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
    // "market" = browsing is allowed without account.
    // Every other action requires authentication.
    if (action !== "market" && !requireAuth()) return;
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
              setActiveTrip({ mode: bookingRide, ...trip, holdId, rideId: (ride as { id: string }).id });
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
              /[?&]demo=1/.test(window.location.search))) && activeTrip.rideId
          ? (
            <RealtimeTripScreen
              key={`v2-${activeTrip.rideId}`}
              rideId={activeTrip.rideId}
              mode={activeTrip.mode as "moto" | "toktok"}
              holdId={activeTrip.holdId}
              onClose={() => {
                setActiveTrip(null);
                setActiveView("orders");
                setActiveTab("orders");
              }}
            />
          )
          : <LiveTracking
            mode={activeTrip.mode}
            pickupCoords={activeTrip.pickupCoords}
            destCoords={activeTrip.destCoords}
            fare={activeTrip.fare}
            holdId={activeTrip.holdId}
            rideId={activeTrip.rideId}
            onClose={() => {
              setActiveTrip(null);
              setActiveView("orders");
              setActiveTab("orders");
            }}
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
    </div>
  );
};

export default Index;
