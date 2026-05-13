import { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";

/**
 * Gate: ensures the user is signed in AND has a complete profile
 * (first_name, last_name, phone). Otherwise routes to /complete-profile or /auth.
 */
export function RequireProfile({ children }: { children: ReactNode }) {
  const { ready, isLoggedIn, isProfileComplete } = useAuth();
  const location = useLocation();
  if (!ready) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }
  if (!isLoggedIn) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/auth?next=${next}`} replace />;
  }
  if (!isProfileComplete) {
    return <Navigate to="/complete-profile" replace />;
  }
  return <>{children}</>;
}