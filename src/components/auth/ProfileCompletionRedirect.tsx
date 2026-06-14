import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";

/**
 * Account-status-aware redirect chain:
 *   1. session + banned/frozen/deleted handled elsewhere
 *   2. incomplete profile → /complete-profile (HARD requirement)
 *
 * Periodic 60-day reconfirmation is intentionally NOT auto-routed here —
 * complete-profile users go straight to their dashboard. /confirm-profile
 * remains reachable manually but is never forced post-login (was perceived
 * as "asks me to confirm my info every login").
 */
export function ProfileCompletionRedirect() {
  const { ready, isLoggedIn, isProfileComplete, profileLoading } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    if (!ready || profileLoading || !isLoggedIn) return;
    const exempt = ["/auth", "/complete-profile", "/confirm-profile", "/no-access"];
    if (exempt.some((p) => location.pathname.startsWith(p))) return;
    if (!isProfileComplete) {
      navigate("/complete-profile", { replace: true });
      return;
    }
  }, [ready, profileLoading, isLoggedIn, isProfileComplete, location.pathname, navigate]);

  return null;
}