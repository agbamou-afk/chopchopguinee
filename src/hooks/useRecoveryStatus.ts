import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import { fetchRecoveryStatus, RecoveryStatus } from "@/lib/recovery/api";

/**
 * Signed-in recovery status. Returns only a boolean + the chosen question
 * labels — never an answer, a hash or the recovery key.
 */
export function useRecoveryStatus() {
  const { isLoggedIn, ready } = useAuth();
  const [status, setStatus] = useState<RecoveryStatus | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    if (!isLoggedIn) {
      setStatus(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    const res = await fetchRecoveryStatus();
    setStatus(res);
    setLoading(false);
  }, [isLoggedIn]);

  useEffect(() => {
    if (!ready) return;
    void reload();
  }, [ready, reload]);

  return { status, loading, reload, configured: status?.configured === true };
}