import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import Auth from "./pages/Auth";
import Admin from "./pages/Admin";
import AgentTopup from "./pages/AgentTopup";
import AgentDashboard from "./pages/AgentDashboard";
import ProfileInfo from "./pages/ProfileInfo";
import Help from "./pages/Help";
import Legal from "./pages/Legal";
import Notifications from "./pages/Notifications";
import NotificationSettings from "./pages/NotificationSettings";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          <Route path="/admin" element={<Admin />} />
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

export default App;
