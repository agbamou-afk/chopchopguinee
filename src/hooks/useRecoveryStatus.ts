import { useCallback, useEffect, useSyncExternalStore } from "react";
import { useAuth } from "@/contexts/AuthContext";
import { fetchRecoveryStatus, RecoveryStatus } from "@/lib/recovery/api";

/**
 * Signed-in recovery status. Returns only a boolean + the chosen question
 * labels — never an answer, a hash or the recovery key.
 *
 * The status lives in ONE module-level store shared by every consumer (the
 * global `RecoverySetupRedirect` gate, the setup page and Compte → Sécurité).
 * A single source of truth is what prevents the "enrolled but bounced back to
 * setup" loop: as soon as the enrollment page revalidates, the global gate
 * observes the same fresh value in the same render pass.
 */

interface StoreState {
  status: RecoveryStatus | null;
  loading: boolean;
}

let state: StoreState = { status: null, loading: true };
const listeners = new Set<() => void>();
let inflight: Promise<RecoveryStatus | null> | null = null;

function emit(next: StoreState) {
  state = next;
  listeners.forEach((l) => l());
}

function subscribe(l: () => void) {
  listeners.add(l);
  return () => listeners.delete(l);
}

function getSnapshot() {
  return state;
}

/** Fetches a fresh status and publishes it to every consumer. */
export async function refreshRecoveryStatus(): Promise<RecoveryStatus | null> {
  if (inflight) return inflight;
  emit({ ...state, loading: true });
  inflight = (async () => {
    const res = await fetchRecoveryStatus();
    emit({ status: res, loading: false });
    return res;
  })();
  try {
    return await inflight;
  } finally {
    inflight = null;
  }
}

/** Clears the shared status (sign-out, tests). */
export function resetRecoveryStatus() {
  inflight = null;
  emit({ status: null, loading: false });
}

export function useRecoveryStatus() {
  const { isLoggedIn, ready } = useAuth();
  const snapshot = useSyncExternalStore(subscribe, getSnapshot);

  const reload = useCallback(async (): Promise<RecoveryStatus | null> => {
    if (!isLoggedIn) {
      resetRecoveryStatus();
      return null;
    }
    return refreshRecoveryStatus();
  }, [isLoggedIn]);

  useEffect(() => {
    if (!ready) return;
    void reload();
  }, [ready, reload]);

  return {
    status: snapshot.status,
    loading: snapshot.loading,
    reload,
    configured: snapshot.status?.configured === true,
  };
}
