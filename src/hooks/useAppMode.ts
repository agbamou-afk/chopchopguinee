import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export type AppMode = "client" | "merchant" | "driver";

const LS_KEY = "cc_app_mode";
/**
 * Short-lived session override written the moment the user switches modes.
 * Beats stale persisted backend mode + stale auth metadata `signupIntent`
 * during the same tab, preventing merchant→client bounce-back races.
 */
const SESSION_OVERRIDE_KEY = "cc_app_mode_override";

function readSessionOverride(): AppMode | null {
  if (typeof window === "undefined") return null;
  try {
    const v = window.sessionStorage.getItem(SESSION_OVERRIDE_KEY);
    return v === "client" || v === "merchant" || v === "driver" ? v : null;
  } catch {
    return null;
  }
}

export function useAppMode() {
  const { user } = useAuth();
  const [mode, setModeState] = useState<AppMode>(() => {
    try {
      const v = typeof window !== "undefined" ? window.localStorage.getItem(LS_KEY) : null;
      return v === "merchant" || v === "driver" ? v : "client";
    } catch {
      return "client";
    }
  });
  const [persistedMode, setPersistedMode] = useState<AppMode | null>(null);
  const [sessionOverride, setSessionOverride] = useState<AppMode | null>(() => readSessionOverride());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) {
      setPersistedMode(null);
      setLoading(false);
      return;
    }
    (async () => {
      const { data } = await (supabase as any)
        .from("user_preferences")
        .select("app_mode")
        .eq("user_id", user.id)
        .maybeSingle();
      if (data?.app_mode === "merchant" || data?.app_mode === "client" || data?.app_mode === "driver") {
        setPersistedMode(data.app_mode);
        setModeState(data.app_mode);
        try { window.localStorage.setItem(LS_KEY, data.app_mode); } catch { /* noop */ }
      } else {
        setPersistedMode(null);
      }
      setLoading(false);
    })();
  }, [user]);

  const setMode = useCallback(async (next: AppMode) => {
    setModeState(next);
    setPersistedMode(next);
    // Write session override synchronously so any routing decision that fires
    // before the backend write completes already sees the new mode.
    try { window.sessionStorage.setItem(SESSION_OVERRIDE_KEY, next); } catch { /* noop */ }
    setSessionOverride(next);
    try { window.localStorage.setItem(LS_KEY, next); } catch { /* noop */ }
    if (!user) return;
    await (supabase as any)
      .from("user_preferences")
      .upsert({ user_id: user.id, app_mode: next }, { onConflict: "user_id" });
  }, [user]);

  // Effective mode used by routing/redirect logic. Override wins until cleared
  // or until the backend persisted mode matches it. Logout clears it.
  const effectiveMode: AppMode | null = sessionOverride ?? persistedMode;

  return { mode, persistedMode, effectiveMode, setMode, loading };
}

/** Clear the session override (e.g. on signOut). */
export function clearAppModeSessionOverride() {
  if (typeof window === "undefined") return;
  try { window.sessionStorage.removeItem(SESSION_OVERRIDE_KEY); } catch { /* noop */ }
}
