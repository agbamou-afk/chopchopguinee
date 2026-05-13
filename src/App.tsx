import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "@/contexts/AuthContext";
import { ProfileCompletionRedirect } from "@/components/auth/ProfileCompletionRedirect";
import { useTopupNotifications } from "@/hooks/useTopupNotifications";
import { useEffect, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { SplashScreen } from "@/components/SplashScreen";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import Auth from "./pages/Auth";
import CompleteProfile from "./pages/CompleteProfile";
import NoAccess from "./pages/NoAccess";
import AgentTopup from "./pages/AgentTopup";
import AgentDashboard from "./pages/AgentDashboard";
import ProfileInfo from "./pages/ProfileInfo";
import Help from "./pages/Help";
import Legal from "./pages/Legal";
import Notifications from "./pages/Notifications";
import NotificationSettings from "./pages/NotificationSettings";
import Unsubscribe from "./pages/Unsubscribe";
import { AdminLayout } from "./components/admin/AdminLayout";
import AdminDashboard from "./pages/admin/AdminDashboard";
import LiveOps from "./pages/admin/LiveOps";
import UsersAdmin from "./pages/admin/UsersAdmin";
import DriversAdmin from "./pages/admin/DriversAdmin";
import MerchantsAdmin from "./pages/admin/MerchantsAdmin";
import VendorsAdmin from "./pages/admin/VendorsAdmin";
import WalletAdmin from "./pages/admin/WalletAdmin";
import WalletReconciliation from "./pages/admin/WalletReconciliation";
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
import AnalyticsAdmin from "./pages/admin/AnalyticsAdmin";
import PrivacySettings from "./pages/PrivacySettings";
import { Analytics } from "@/lib/analytics/AnalyticsService";

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

  useEffect(() => {
    Analytics.init();
  }, []);

  return (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <AnimatePresence>{showSplash && <SplashScreen />}</AnimatePresence>
      <BrowserRouter>
      <AuthProvider>
        <ProfileCompletionRedirect />
        <TopupNotificationsMount />
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          <Route path="/complete-profile" element={<CompleteProfile />} />
          <Route path="/no-access" element={<NoAccess />} />
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<AdminDashboard />} />
            <Route path="live" element={<LiveOps />} />
            <Route path="users" element={<UsersAdmin />} />
            <Route path="drivers" element={<DriversAdmin />} />
            <Route path="merchants" element={<MerchantsAdmin />} />
            <Route path="vendors" element={<VendorsAdmin />} />
            <Route path="wallet" element={<WalletAdmin />} />
            <Route path="wallet/reconciliation" element={<WalletReconciliation />} />
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
            <Route path="analytics" element={<AnalyticsAdmin />} />
          </Route>
          <Route path="/agent" element={<AgentDashboard />} />
          <Route path="/agent/topup" element={<AgentTopup />} />
          <Route path="/profile" element={<ProfileInfo />} />
          <Route path="/help" element={<Help />} />
          <Route path="/legal" element={<Legal />} />
          <Route path="/notifications" element={<Notifications />} />
          <Route path="/settings/notifications" element={<NotificationSettings />} />
          <Route path="/settings/privacy" element={<PrivacySettings />} />
          <Route path="/unsubscribe" element={<Unsubscribe />} />
          {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
          <Route path="*" element={<NotFound />} />
        </Routes>
      </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
  );
};

export default App;
