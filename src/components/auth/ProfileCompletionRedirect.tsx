import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";

/**
 * Account-status-aware redirect chain (priority order):
 *   1. session + banned/frozen/deleted handled elsewhere (FreezeGate, AuthContext)
 *   2. incomplete profile → /complete-profile (HARD requirement)
 *   3. 60-day reconfirmation due → /confirm-profile (soft, can be confirmed
 *      in one tap)
 *
 * Frozen/banned/deleted users never reach this chain because AuthContext signs
 * them out (deleted/banned) and FreezeGate intercepts frozen sessions earlier.
 */
export function ProfileCompletionRedirect() {
  const { ready, isLoggedIn, isProfileComplete, profileLoading, needsProfileReconfirmation } = useAuth();
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
    if (needsProfileReconfirmation) {
      navigate("/confirm-profile", { replace: true });
    }
  }, [ready, profileLoading, isLoggedIn, isProfileComplete, needsProfileReconfirmation, location.pathname, navigate]);

  return null;
}