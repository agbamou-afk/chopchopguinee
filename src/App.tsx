import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "@/contexts/AuthContext";
import { AppEnvProvider } from "@/contexts/AppEnvContext";
import { OfflineBanner } from "@/components/system/OfflineBanner";
import { InstallPrompt } from "@/components/system/InstallPrompt";
import { ProfileCompletionRedirect } from "@/components/auth/ProfileCompletionRedirect";
import { useTopupNotifications } from "@/hooks/useTopupNotifications";
import { useEffect, useState, lazy, Suspense } from "react";
import { AnimatePresence } from "framer-motion";
import { SplashScreen } from "@/components/SplashScreen";

function TopupNotificationsMount() {
  useTopupNotifications();
  return null;
}
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
const AdminLayout = lazy(() => import("./components/admin/AdminLayout").then(m => ({ default: m.AdminLayout })));
const AdminDashboard = lazy(() => import("./pages/admin/AdminDashboard"));
const LiveOps = lazy(() => import("./pages/admin/LiveOps"));
const UsersAdmin = lazy(() => import("./pages/admin/UsersAdmin"));
const DriversAdmin = lazy(() => import("./pages/admin/DriversAdmin"));
const MerchantsAdmin = lazy(() => import("./pages/admin/MerchantsAdmin"));
const VendorsAdmin = lazy(() => import("./pages/admin/VendorsAdmin"));
const WalletAdmin = lazy(() => import("./pages/admin/WalletAdmin"));
const WalletReconciliation = lazy(() => import("./pages/admin/WalletReconciliation"));
const PricingAdmin = lazy(() => import("./pages/admin/PricingAdmin"));
const OrdersAdmin = lazy(() => import("./pages/admin/OrdersAdmin"));
const RepasAdmin = lazy(() => import("./pages/admin/RepasAdmin"));
const MarcheAdmin = lazy(() => import("./pages/admin/MarcheAdmin"));
const SupportAdmin = lazy(() => import("./pages/admin/SupportAdmin"));
const RiskAdmin = lazy(() => import("./pages/admin/RiskAdmin"));
const NotificationsAdmin = lazy(() => import("./pages/admin/NotificationsAdmin"));
const PromotionsAdmin = lazy(() => import("./pages/admin/PromotionsAdmin"));
const ReportsAdmin = lazy(() => import("./pages/admin/ReportsAdmin"));
const ZonesAdmin = lazy(() => import("./pages/admin/ZonesAdmin"));
const FlagsAdmin = lazy(() => import("./pages/admin/FlagsAdmin"));
const SettingsAdmin = lazy(() => import("./pages/admin/SettingsAdmin"));
const AdminsAdmin = lazy(() => import("./pages/admin/AdminsAdmin"));
const AuditAdmin = lazy(() => import("./pages/admin/AuditAdmin"));
const AnalyticsAdmin = lazy(() => import("./pages/admin/AnalyticsAdmin"));
const DriverApply = lazy(() => import("./pages/DriverApply"));
import PrivacySettings from "./pages/PrivacySettings";
import OfflinePage from "./pages/Offline";
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
    <AppEnvProvider>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <OfflineBanner />
      <AnimatePresence>{showSplash && <SplashScreen />}</AnimatePresence>
      <BrowserRouter>
      <AuthProvider>
        <ProfileCompletionRedirect />
        <TopupNotificationsMount />
        <InstallPrompt />
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          <Route path="/complete-profile" element={<CompleteProfile />} />
          <Route path="/no-access" element={<NoAccess />} />
          <Route path="/admin" element={<Suspense fallback={null}><AdminLayout /></Suspense>}>
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
          <Route path="/offline" element={<OfflinePage />} />
          <Route path="/driver/apply" element={<Suspense fallback={null}><DriverApply /></Suspense>} />
          {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
          <Route path="*" element={<NotFound />} />
        </Routes>
      </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
    </AppEnvProvider>
  </QueryClientProvider>
  );
};

export default App;
