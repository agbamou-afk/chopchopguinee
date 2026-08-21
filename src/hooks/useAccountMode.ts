import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import {
  CLIENT_ONLY,
  fetchAccountModeContext,
  type AccountMode,
  type AccountModeContext,
} from "@/lib/identity/accountMode";

/**
 * Node 5 · A8 — client read of the server-authoritative workspace context.
 *
 * The UI may only offer modes returned by the server. A mode the server did
 * not return is never selectable, regardless of local storage state.
 */
export function useAccountMode() {
  const { isLoggedIn, ready } = useAuth();
  const [context, setContext] = useState<AccountModeContext>(CLIENT_ONLY);
  const [loading, setLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!isLoggedIn) {
      setContext(CLIENT_ONLY);
      setLoading(false);
      return;
    }
    setLoading(true);
    setContext(await fetchAccountModeContext());
    setLoading(false);
  }, [isLoggedIn]);

  useEffect(() => {
    if (!ready) return;
    void refetch();
  }, [ready, refetch]);

  return {
    ...context,
    loading: loading || !ready,
    /** Multi-workspace accounts are the only ones that see a switcher. */
    canSwitch: context.availableModes.length > 1,
    isAvailable: (mode: AccountMode) => context.availableModes.includes(mode),
    refetch,
  };
}
