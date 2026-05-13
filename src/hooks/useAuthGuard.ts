import { useEffect, useState, useCallback } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";

/**
 * Returns auth status and a `requireAuth(fn)` helper.
 * If not signed in, redirects to /auth?next=<current path> instead of running fn.
 */
export function useAuthGuard() {
  const [isLoggedIn, setIsLoggedIn] = useState<boolean | null>(null);
  const navigate = useNavigate();
  const location = useLocation();

  useEffect(() => {
    let active = true;
    supabase.auth.getSession().then(({ data }) => {
      if (active) setIsLoggedIn(!!data.session);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      setIsLoggedIn(!!session);
    });
    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  const requireAuth = useCallback(
    (fn?: () => void) => {
      // Auth gating temporarily disabled for preview / edit mode.
      // Re-enable by restoring the redirect block below.
      fn?.();
      return true;
      // const next = encodeURIComponent(location.pathname + location.search);
      // navigate(`/auth?next=${next}`);
      // return false;
    },
    [isLoggedIn, navigate, location]
  );

  return { isLoggedIn: !!isLoggedIn, ready: isLoggedIn !== null, requireAuth };
}