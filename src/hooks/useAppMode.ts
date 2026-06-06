import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export type AppMode = "client" | "merchant" | "driver";

const LS_KEY = "cc_app_mode";

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
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) {
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
        setModeState(data.app_mode);
        try { window.localStorage.setItem(LS_KEY, data.app_mode); } catch { /* noop */ }
      }
      setLoading(false);
    })();
  }, [user]);

  const setMode = useCallback(async (next: AppMode) => {
    setModeState(next);
    try { window.localStorage.setItem(LS_KEY, next); } catch { /* noop */ }
    if (!user) return;
    await (supabase as any)
      .from("user_preferences")
      .upsert({ user_id: user.id, app_mode: next }, { onConflict: "user_id" });
  }, [user]);

  return { mode, setMode, loading };
}
