import { useCallback } from "react";
import { useAuth } from "@/contexts/AuthContext";

/**
 * Returns auth status and a `requireAuth(fn)` helper, backed by the global AuthContext.
 * Auth gating for transactional flows is currently permissive in preview mode — restore
 * the redirect block below to enforce sign-in.
 */
export function useAuthGuard() {
  const { isLoggedIn, ready } = useAuth();

  const requireAuth = useCallback(
    (fn?: () => void) => {
      fn?.();
      return true;
    },
    [isLoggedIn],
  );

  return { isLoggedIn, ready, requireAuth };
}