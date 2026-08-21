import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { clearMerchantIntent, hasStoredMerchantIntent } from "@/lib/merchantRouting";
import { fetchAccountModeContext, setAccountMode } from "@/lib/identity/accountMode";
import { toast } from "@/hooks/use-toast";

export type AppMode = "client" | "merchant" | "driver";

const LS_KEY = "cc_app_mode";
/**
 * Short-lived session override written the moment the user switches modes.
 * Beats stale persisted backend mode + stale auth metadata `signupIntent`
 * during the same tab, preventing merchant→client bounce-back races.
 */
const SESSION_OVERRIDE_KEY = "cc_app_mode_override";
const DRIVER_CHOICE_KEY = "cc_driver_mode_choice";

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
      // Node 5 · A8: the server returns the EFFECTIVE mode, i.e. the stored
      // preference already validated against the active professional lane.
      // A stale professional preference degrades to "client" server-side.
      const ctx = await fetchAccountModeContext();
      const effective = ctx.effectiveMode;
      setPersistedMode(effective);
      setModeState(effective);
      try { window.localStorage.setItem(LS_KEY, effective); } catch { /* noop */ }
      if (readSessionOverride() && !ctx.availableModes.includes(readSessionOverride() as AppMode)) {
        // an unlawful local override can never survive a server read
        clearAppModeSessionOverride();
        setSessionOverride(null);
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
    const res = await setAccountMode(next);
    if (res.refused) {
      // server refused the professional workspace — realign the client
      setModeState(res.effectiveMode);
      setPersistedMode(res.effectiveMode);
      setSessionOverride(res.effectiveMode);
      try { window.sessionStorage.setItem(SESSION_OVERRIDE_KEY, res.effectiveMode); } catch { /* noop */ }
      try { window.localStorage.setItem(LS_KEY, res.effectiveMode); } catch { /* noop */ }
    }
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

/**
 * Canonical mode-switch helper. Every UI entry point (top-right
 * MerchantHub toggle, profile menu, etc.) MUST go through this so the
 * sequence is always identical:
 *
 *   1. write session override SYNC  (beats Index merchant-redirect race)
 *   2. clear merchant signup intent SYNC
 *   3. align driver-mode choice SYNC
 *   4. update local React caches SYNC
 *   5. fire-and-forget validated backend write (no await before navigation)
 *   6. navigate with explicit `?mode=` query (Index defensively honors it)
 *
 * The navigation MUST NOT wait on the backend. The session override + URL
 * query are enough to keep Index from bouncing back to /merchant/hub.
 *
 * Node 5 · A8: persistence goes through the validated server RPC, never a
 * direct preference write — an unlawful professional mode is degraded to
 * "client" by the server and by the preference guard.
 */
export function switchAppModeSync(next: AppMode, userId: string | null | undefined) {
  try { window.sessionStorage.setItem(SESSION_OVERRIDE_KEY, next); } catch { /* noop */ }
  try { window.localStorage.setItem(LS_KEY, next); } catch { /* noop */ }
  if (next === "client") {
    try { clearMerchantIntent(); } catch { /* noop */ }
    try { window.sessionStorage.setItem(DRIVER_CHOICE_KEY, "client"); } catch { /* noop */ }
  } else if (next === "driver") {
    try { window.sessionStorage.setItem(DRIVER_CHOICE_KEY, "driver"); } catch { /* noop */ }
  }
  if (userId) {
    // fire-and-forget — UI must not wait on the round-trip
    void setAccountMode(next).then((res) => {
      if (!res.refused) return;
      try { window.sessionStorage.setItem(SESSION_OVERRIDE_KEY, res.effectiveMode); } catch { /* noop */ }
      try { window.localStorage.setItem(LS_KEY, res.effectiveMode); } catch { /* noop */ }
    });
  }
  if (import.meta.env.DEV) {
    // eslint-disable-next-line no-console
    console.debug("[switch-mode]", {
      next,
      wroteOverride: window.sessionStorage.getItem(SESSION_OVERRIDE_KEY),
      hasStoredMerchantIntent: hasStoredMerchantIntent(),
    });
  }
}

/**
 * React hook wrapping `switchAppModeSync` with navigation + toast. Use
 * from any mode-switch button.
 */
export function useSwitchAppMode() {
  const { user } = useAuth();
  const navigate = useNavigate();
  return useCallback((next: AppMode, opts?: { silent?: boolean }) => {
    switchAppModeSync(next, user?.id);
    const target = next === "merchant" ? "/merchant/hub" : `/?mode=${next}`;
    navigate(target, { replace: true });
    if (!opts?.silent) {
      const label = next === "merchant"
        ? "Mode marchand activé."
        : next === "driver"
        ? "Mode chauffeur activé."
        : "Mode client activé.";
      try { toast({ title: label }); } catch { /* noop */ }
    }
  }, [user?.id, navigate]);
}
