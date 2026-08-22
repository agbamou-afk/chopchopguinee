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
 *
 * Identity safety: the store is keyed by the canonical authenticated UUID.
 * A snapshot belonging to user A can never be observed as user B's status,
 * and a fetch started for A can never publish after sign-out or after B
 * became current (request-generation suppression). Memory only — nothing is
 * ever persisted to local/session storage.
 */

interface StoreState {
  /** Owner of the snapshot. `null` = signed out / cleared. */
  uid: string | null;
  status: RecoveryStatus | null;
  loading: boolean;
}

let state: StoreState = { uid: null, status: null, loading: true };
const listeners = new Set<() => void>();

/** Monotonic token. Any bump invalidates every in-flight response. */
let generation = 0;
let inflight: { uid: string; token: number; promise: Promise<RecoveryStatus | null> } | null = null;

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

/**
 * Binds the store to the current authenticated UUID. Synchronously drops the
 * previous owner's snapshot and invalidates its in-flight request.
 */
export function setRecoveryStatusUser(uid: string | null) {
  if (state.uid === uid) return;
  generation += 1;
  inflight = null;
  emit({ uid, status: null, loading: uid !== null });
}

/** Fetches a fresh status for the current UUID and publishes it. */
export async function refreshRecoveryStatus(force = false): Promise<RecoveryStatus | null> {
  const uid = state.uid;
  if (!uid) return null;

  if (inflight && inflight.uid === uid && inflight.token === generation && !force) {
    return inflight.promise;
  }

  const token = (generation += 1);
  if (!state.loading) emit({ ...state, loading: true });

  const promise = (async () => {
    let res: RecoveryStatus | null = null;
    try {
      res = await fetchRecoveryStatus();
    } catch {
      res = null;
    }
    // Stale-response suppression: sign-out, account switch or a newer forced
    // request happened while this one was flying.
    if (token !== generation || state.uid !== uid) return null;
    inflight = null;
    emit({ uid, status: res, loading: false });
    return res;
  })();

  inflight = { uid, token, promise };
  return promise;
}

/** Clears the shared status (sign-out, tests). */
export function resetRecoveryStatus() {
  generation += 1;
  inflight = null;
  emit({ uid: null, status: null, loading: false });
}

export function useRecoveryStatus() {
  const { isLoggedIn, ready, user } = useAuth();
  const uid = isLoggedIn ? user?.id ?? null : null;
  const snapshot = useSyncExternalStore(subscribe, getSnapshot);

  const reload = useCallback(
    async (force = false): Promise<RecoveryStatus | null> => {
      if (!uid) {
        resetRecoveryStatus();
        return null;
      }
      setRecoveryStatusUser(uid);
      return refreshRecoveryStatus(force);
    },
    [uid],
  );

  useEffect(() => {
    if (!ready) return;
    void reload();
  }, [ready, reload]);

  // Never let another UUID's snapshot drive routing, not even for one render.
  const owned = snapshot.uid === uid && uid !== null;
  const status = owned ? snapshot.status : null;

  return {
    status,
    loading: owned ? snapshot.loading : uid !== null,
    reload,
    configured: status?.configured === true,
  };
}
