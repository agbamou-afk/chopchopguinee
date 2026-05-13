import { useState, useEffect } from "react";
import { AnimatePresence } from "framer-motion";
import { SplashScreen } from "@/components/SplashScreen";
import { UserHome } from "@/components/views/UserHome";
import { DriverHome } from "@/components/views/DriverHome";
import { RideBooking } from "@/components/ride/RideBooking";
import { LiveTracking, type TrackingMode } from "@/components/tracking/LiveTracking";
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

export type RideType = "moto" | "toktok" | null;
export type ActiveView = "home" | "food" | "market" | "wallet" | "profile" | "orders";

const Index = () => {
  const [showSplash, setShowSplash] = useState(true);
  const [isDriverMode, setIsDriverMode] = useState(false);
  const [activeTab, setActiveTab] = useState("home");
  const [activeView, setActiveView] = useState<ActiveView>("home");
  const [bookingRide, setBookingRide] = useState<RideType>(null);
  const [activeTrip, setActiveTrip] = useState<{
    mode: TrackingMode;
    pickupCoords: [number, number];
    destCoords?: [number, number];
    fare: number;
    holdId?: string | null;
    rideId?: string | null;
  } | null>(null);
  const [showScanner, setShowScanner] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setShowSplash(false), 4400);
    return () => clearTimeout(t);
  }, []);

  const handleAction = (action: string) => {
    switch (action) {
      case "moto":
        setBookingRide("moto");
        break;
      case "toktok":
        setBookingRide("toktok");
        break;
      case "food":
        setActiveView("food");
        break;
      case "market":
        setActiveView("market");
        break;
      case "send":
        setActiveView("wallet");
        setActiveTab("wallet");
        break;
      case "scan":
        setShowScanner(true);
        break;
      default:
        break;
    }
  };

  const handleTabChange = (tab: string) => {
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
            onToggleDriverMode={() => setIsDriverMode(true)}
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
      <AnimatePresence>
        {showSplash && <SplashScreen />}
      </AnimatePresence>

      <AnimatePresence mode="wait">
        {bookingRide && (
          <RideBooking
            type={bookingRide}
            onClose={() => setBookingRide(null)}
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
              toast({
                title: "Fonds réservés",
                description: `${new Intl.NumberFormat("fr-GN").format(holdAmount)} GNF bloqués jusqu'à la fin de course.`,
              });
            }}
          />
        )}
        {activeTrip && (
          <LiveTracking
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
        <>
          {isDriverMode ? renderDriverView() : renderUserView()}
          <BottomNav
            activeTab={activeTab}
            onTabChange={handleTabChange}
            isDriverMode={isDriverMode}
            onScanClick={() => handleAction("scan")}
          />
        </>
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
