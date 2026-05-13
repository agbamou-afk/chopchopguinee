import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { useEffect, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { SplashScreen } from "@/components/SplashScreen";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import Auth from "./pages/Auth";
import AgentTopup from "./pages/AgentTopup";
import AgentDashboard from "./pages/AgentDashboard";
import ProfileInfo from "./pages/ProfileInfo";
import Help from "./pages/Help";
import Legal from "./pages/Legal";
import Notifications from "./pages/Notifications";
import NotificationSettings from "./pages/NotificationSettings";
import { AdminLayout } from "./components/admin/AdminLayout";
import AdminDashboard from "./pages/admin/AdminDashboard";
import LiveOps from "./pages/admin/LiveOps";
import UsersAdmin from "./pages/admin/UsersAdmin";
import DriversAdmin from "./pages/admin/DriversAdmin";
import MerchantsAdmin from "./pages/admin/MerchantsAdmin";
import VendorsAdmin from "./pages/admin/VendorsAdmin";
import WalletAdmin from "./pages/admin/WalletAdmin";
import PricingAdmin from "./pages/admin/PricingAdmin";
import OrdersAdmin from "./pages/admin/OrdersAdmin";
import RepasAdmin from "./pages/admin/RepasAdmin";
import MarcheAdmin from "./pages/admin/MarcheAdmin";
import SupportAdmin from "./pages/admin/SupportAdmin";
import RiskAdmin from "./pages/admin/RiskAdmin";
import NotificationsAdmin from "./pages/admin/NotificationsAdmin";
import PromotionsAdmin from "./pages/admin/PromotionsAdmin";
import ReportsAdmin from "./pages/admin/ReportsAdmin";
import ZonesAdmin from "./pages/admin/ZonesAdmin";
import FlagsAdmin from "./pages/admin/FlagsAdmin";
import SettingsAdmin from "./pages/admin/SettingsAdmin";
import AdminsAdmin from "./pages/admin/AdminsAdmin";
import AuditAdmin from "./pages/admin/AuditAdmin";

const queryClient = new QueryClient();

const App = () => {
  const [showSplash, setShowSplash] = useState(() => {
    if (typeof window === "undefined") return true;
    return sessionStorage.getItem("cc_splash_shown") !== "1";
  });

  useEffect(() => {
    if (!showSplash) return;
    const t = setTimeout(() => {
      setShowSplash(false);
      try { sessionStorage.setItem("cc_splash_shown", "1"); } catch {}
    }, 4400);
    return () => clearTimeout(t);
  }, [showSplash]);

  return (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <AnimatePresence>{showSplash && <SplashScreen />}</AnimatePresence>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<AdminDashboard />} />
            <Route path="live" element={<LiveOps />} />
            <Route path="users" element={<UsersAdmin />} />
            <Route path="drivers" element={<DriversAdmin />} />
            <Route path="merchants" element={<MerchantsAdmin />} />
            <Route path="vendors" element={<VendorsAdmin />} />
            <Route path="wallet" element={<WalletAdmin />} />
            <Route path="pricing" element={<PricingAdmin />} />
            <Route path="orders" element={<OrdersAdmin />} />
            <Route path="repas" element={<RepasAdmin />} />
            <Route path="marche" element={<MarcheAdmin />} />
            <Route path="support" element={<SupportAdmin />} />
            <Route path="risk" element={<RiskAdmin />} />
            <Route path="notifications" element={<NotificationsAdmin />} />
            <Route path="promotions" element={<PromotionsAdmin />} />
            <Route path="reports" element={<ReportsAdmin />} />
            <Route path="zones" element={<ZonesAdmin />} />
            <Route path="flags" element={<FlagsAdmin />} />
            <Route path="settings" element={<SettingsAdmin />} />
            <Route path="admins" element={<AdminsAdmin />} />
            <Route path="audit" element={<AuditAdmin />} />
          </Route>
          <Route path="/agent" element={<AgentDashboard />} />
          <Route path="/agent/topup" element={<AgentTopup />} />
          <Route path="/profile" element={<ProfileInfo />} />
          <Route path="/help" element={<Help />} />
          <Route path="/legal" element={<Legal />} />
          <Route path="/notifications" element={<Notifications />} />
          <Route path="/settings/notifications" element={<NotificationSettings />} />
          {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
  );
};

export default App;
