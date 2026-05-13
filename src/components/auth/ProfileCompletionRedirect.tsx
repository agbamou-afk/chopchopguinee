import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";

/**
 * Watches the global session and pushes any logged-in user with an incomplete
 * profile to /complete-profile. Skipped on /auth and /complete-profile so the
 * user can actually finish those flows.
 */
export function ProfileCompletionRedirect() {
  const { ready, isLoggedIn, isProfileComplete } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    if (!ready || !isLoggedIn || isProfileComplete) return;
    const exempt = ["/auth", "/complete-profile", "/no-access"];
    if (exempt.some((p) => location.pathname.startsWith(p))) return;
    navigate("/complete-profile", { replace: true });
  }, [ready, isLoggedIn, isProfileComplete, location.pathname, navigate]);

  return null;
}