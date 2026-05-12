import { useState, useEffect } from "react";
import { AnimatePresence } from "framer-motion";
import { SplashScreen } from "@/components/SplashScreen";
import { UserHome } from "@/components/views/UserHome";
import { DriverHome } from "@/components/views/DriverHome";
import { RideBooking } from "@/components/ride/RideBooking";
import { FoodView } from "@/components/views/FoodView";
import { MarketView } from "@/components/views/MarketView";
import { WalletView } from "@/components/views/WalletView";
import { ProfileView } from "@/components/views/ProfileView";
import { OrdersView } from "@/components/views/OrdersView";
import { DriverOrdersView } from "@/components/views/DriverOrdersView";
import { DriverEarningsView } from "@/components/views/DriverEarningsView";
import { BottomNav } from "@/components/ui/BottomNav";

export type RideType = "moto" | "toktok" | null;
export type ActiveView = "home" | "food" | "market" | "wallet" | "profile" | "orders";

const Index = () => {
  const [showSplash, setShowSplash] = useState(true);
  const [isDriverMode, setIsDriverMode] = useState(false);
  const [activeTab, setActiveTab] = useState("home");
  const [activeView, setActiveView] = useState<ActiveView>("home");
  const [bookingRide, setBookingRide] = useState<RideType>(null);

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
      case "scan":
        setActiveView("wallet");
        setActiveTab("wallet");
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
      <AnimatePresence>
        {showSplash && <SplashScreen />}
      </AnimatePresence>

      <AnimatePresence mode="wait">
        {bookingRide && (
          <RideBooking
            type={bookingRide}
            onClose={() => setBookingRide(null)}
            onBook={() => {
              setBookingRide(null);
              setActiveView("orders");
              setActiveTab("orders");
            }}
          />
        )}
      </AnimatePresence>

      {!bookingRide && (
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
    </div>
  );
};

export default Index;
