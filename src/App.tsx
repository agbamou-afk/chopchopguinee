import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider, useAuth } from "@/contexts/AuthContext";
import { AppEnvProvider } from "@/contexts/AppEnvContext";
import { OfflineBanner } from "@/components/system/OfflineBanner";
import { InstallPrompt } from "@/components/system/InstallPrompt";
import { ProfileCompletionRedirect } from "@/components/auth/ProfileCompletionRedirect";
import { FrozenAccountScreen } from "@/components/account/FrozenAccountScreen";
import { useTopupNotifications } from "@/hooks/useTopupNotifications";
import { useEffect, useState, lazy, Suspense } from "react";
import { AnimatePresence } from "framer-motion";
import { SplashScreen } from "@/components/SplashScreen";
import { isSandboxMode } from "@/lib/runtimeMode";
import { useLocation } from "react-router-dom";

const FREEZE_ALLOWED_PATHS = ["/auth", "/legal", "/privacy", "/terms", "/help", "/unsubscribe", "/offline"];

function FreezeGate({ children }: { children: React.ReactNode }) {
  const { isFrozen, ready } = useAuth();
  const location = useLocation();
  if (!ready || !isFrozen) return <>{children}</>;
  const allowed = FREEZE_ALLOWED_PATHS.some((p) => location.pathname.startsWith(p));
  if (allowed) return <>{children}</>;
  return <FrozenAccountScreen />;
}

function TopupNotificationsMount() {
  useTopupNotifications();
  return null;
}
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import Auth from "./pages/Auth";
import CompleteProfile from "./pages/CompleteProfile";
import ConfirmProfile from "./pages/ConfirmProfile";
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
const RepasPayments = lazy(() => import("./pages/admin/RepasPayments"));
const MarcheAdmin = lazy(() => import("./pages/admin/MarcheAdmin"));
const SupportAdmin = lazy(() => import("./pages/admin/SupportAdmin"));
const RiskAdmin = lazy(() => import("./pages/admin/RiskAdmin"));
const NotificationsAdmin = lazy(() => import("./pages/admin/NotificationsAdmin"));
const PromotionsAdmin = lazy(() => import("./pages/admin/PromotionsAdmin"));
const ReportsAdmin = lazy(() => import("./pages/admin/ReportsAdmin"));
const ZonesAdmin = lazy(() => import("./pages/admin/ZonesAdmin"));
const MapZonesAdmin = lazy(() => import("./pages/admin/MapZonesAdmin"));
const MapPlacesAdmin = lazy(() => import("./pages/admin/MapPlacesAdmin"));
const MapTariffsAdmin = lazy(() => import("./pages/admin/MapTariffsAdmin"));
const MapDuplicatesAdmin = lazy(() => import("./pages/admin/MapDuplicatesAdmin"));
const FlagsAdmin = lazy(() => import("./pages/admin/FlagsAdmin"));
const SettingsAdmin = lazy(() => import("./pages/admin/SettingsAdmin"));
const AdminsAdmin = lazy(() => import("./pages/admin/AdminsAdmin"));
const AuditAdmin = lazy(() => import("./pages/admin/AuditAdmin"));
const AnalyticsAdmin = lazy(() => import("./pages/admin/AnalyticsAdmin"));
const PaymentsAdmin = lazy(() => import("./pages/admin/PaymentsAdmin"));
const PilotCommandCenter = lazy(() => import("./pages/admin/PilotCommandCenter"));
const DriverGroupsAdmin = lazy(() => import("./pages/admin/DriverGroupsAdmin"));
const LeaderPortal = lazy(() => import("./pages/LeaderPortal"));
const DriverApply = lazy(() => import("./pages/DriverApply"));
const MerchantQR = lazy(() => import("./pages/MerchantQR"));
const Merchant = lazy(() => import("./pages/Merchant"));
const MerchantOnboarding = lazy(() => import("./pages/MerchantOnboarding"));
const MerchantOnboardingSlides = lazy(() => import("./pages/MerchantOnboardingSlides"));
const MerchantApply = lazy(() => import("./pages/MerchantApply"));
const PublicStorefront = lazy(() => import("./pages/PublicStorefront"));
import PrivacySettings from "./pages/PrivacySettings";
import OfflinePage from "./pages/Offline";
import Terms from "./pages/Terms";
import Privacy from "./pages/Privacy";
import PermissionCenter from "./pages/PermissionCenter";
import { LegalAcceptanceModal } from "./components/legal/LegalAcceptanceModal";
import { Analytics } from "@/lib/analytics/AnalyticsService";
const FieldTestingPanel = lazy(() =>
  import("./components/devtools/FieldTestingPanel").then(m => ({ default: m.FieldTestingPanel }))
);
const DemoTestPanel = import.meta.env.DEV
  ? lazy(() => import("./components/devtools/DemoTestPanel").then(m => ({ default: m.DemoTestPanel })))
  : null;
const SandboxOpsPanel = lazy(() =>
  import("./components/devtools/SandboxOpsPanel").then(m => ({ default: m.SandboxOpsPanel }))
);

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
      <Sonner />
      <OfflineBanner />
      <AnimatePresence>{showSplash && <SplashScreen />}</AnimatePresence>
      <BrowserRouter>
      <AuthProvider>
        <ProfileCompletionRedirect />
        <TopupNotificationsMount />
        <InstallPrompt />
        <LegalAcceptanceModal />
        {(isSandboxMode() ||
          (typeof window !== "undefined" &&
            /[?&](field|sandbox|debug)=1/.test(window.location.search))) && (
          <Suspense fallback={null}><FieldTestingPanel /></Suspense>
        )}
        {DemoTestPanel && (isSandboxMode() ||
          (typeof window !== "undefined" &&
            /[?&](field|sandbox|debug)=1/.test(window.location.search))) && (
          <Suspense fallback={null}><DemoTestPanel /></Suspense>
        )}
        {(isSandboxMode() ||
          (typeof window !== "undefined" &&
            /[?&](sandbox|debug)=1/.test(window.location.search))) && (
          <Suspense fallback={null}><SandboxOpsPanel /></Suspense>
        )}
        <FreezeGate>
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          <Route path="/complete-profile" element={<CompleteProfile />} />
          <Route path="/confirm-profile" element={<ConfirmProfile />} />
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
            <Route path="repas/payments" element={<RepasPayments />} />
            <Route path="marche" element={<MarcheAdmin />} />
            <Route path="support" element={<SupportAdmin />} />
            <Route path="risk" element={<RiskAdmin />} />
            <Route path="notifications" element={<NotificationsAdmin />} />
            <Route path="promotions" element={<PromotionsAdmin />} />
            <Route path="reports" element={<ReportsAdmin />} />
            <Route path="zones" element={<ZonesAdmin />} />
            <Route path="map/zones" element={<MapZonesAdmin />} />
            <Route path="map/places" element={<MapPlacesAdmin />} />
            <Route path="map/tarifs" element={<MapTariffsAdmin />} />
            <Route path="map/duplicates" element={<MapDuplicatesAdmin />} />
            <Route path="flags" element={<FlagsAdmin />} />
            <Route path="settings" element={<SettingsAdmin />} />
            <Route path="admins" element={<AdminsAdmin />} />
            <Route path="audit" element={<AuditAdmin />} />
            <Route path="analytics" element={<AnalyticsAdmin />} />
            <Route path="payments" element={<PaymentsAdmin />} />
            <Route path="pilot-command" element={<PilotCommandCenter />} />
            <Route path="driver-groups" element={<DriverGroupsAdmin />} />
          </Route>
          <Route path="/agent" element={<AgentDashboard />} />
          <Route path="/agent/topup" element={<AgentTopup />} />
          <Route path="/profile" element={<ProfileInfo />} />
          <Route path="/help" element={<Help />} />
          <Route path="/legal" element={<Legal />} />
          <Route path="/notifications" element={<Notifications />} />
          <Route path="/settings/notifications" element={<NotificationSettings />} />
          <Route path="/settings/privacy" element={<PrivacySettings />} />
          <Route path="/settings/permissions" element={<PermissionCenter />} />
          <Route path="/terms" element={<Terms />} />
          <Route path="/privacy" element={<Privacy />} />
          <Route path="/unsubscribe" element={<Unsubscribe />} />
          <Route path="/offline" element={<OfflinePage />} />
          <Route path="/driver/apply" element={<Suspense fallback={null}><DriverApply /></Suspense>} />
          <Route path="/merchant" element={<Suspense fallback={null}><MerchantQR /></Suspense>} />
          <Route path="/merchant/hub" element={<Suspense fallback={null}><Merchant /></Suspense>} />
          <Route path="/merchant/onboarding" element={<Suspense fallback={null}><MerchantOnboarding /></Suspense>} />
          <Route path="/merchant/onboarding-slides" element={<Suspense fallback={null}><MerchantOnboardingSlides /></Suspense>} />
          <Route path="/merchant/apply" element={<Suspense fallback={null}><MerchantApply /></Suspense>} />
          <Route path="/devenir-marchand" element={<Suspense fallback={null}><MerchantApply /></Suspense>} />
          <Route path="/marche/boutique/:slug" element={<Suspense fallback={null}><PublicStorefront /></Suspense>} />
          <Route path="/leader" element={<Suspense fallback={null}><LeaderPortal /></Suspense>} />
          {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
          <Route path="*" element={<NotFound />} />
        </Routes>
        </FreezeGate>
      </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
    </AppEnvProvider>
  </QueryClientProvider>
  );
};

export default App;
