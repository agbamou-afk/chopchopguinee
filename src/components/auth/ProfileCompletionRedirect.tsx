import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";

/**
 * Watches the global session and pushes any logged-in user with an incomplete
 * profile to /complete-profile. Skipped on /auth and /complete-profile so the
 * user can actually finish those flows.
 */
export function ProfileCompletionRedirect() {
  const { ready, isLoggedIn, isProfileComplete, profileLoading } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    // Wait until profile fetch finishes — otherwise returning users with a
    // complete profile briefly look "incomplete" and get bounced to
    // /complete-profile on every login.
    if (!ready || profileLoading || !isLoggedIn || isProfileComplete) return;
    const exempt = ["/auth", "/complete-profile", "/no-access"];
    if (exempt.some((p) => location.pathname.startsWith(p))) return;
    navigate("/complete-profile", { replace: true });
  }, [ready, profileLoading, isLoggedIn, isProfileComplete, location.pathname, navigate]);

  return null;
}