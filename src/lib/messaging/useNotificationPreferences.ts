import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { NotificationPreferences } from "./types";
import { defaultPreferences } from "./types";

/**
 * Per-user notification preferences (channel + topic toggles).
 * Backed by `public.notification_preferences`. Falls back to defaults when the user is anonymous.
 */
export function useNotificationPreferences() {
  const [prefs, setPrefs] = useState<NotificationPreferences>(defaultPreferences);
  const [userId, setUserId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id ?? null;
      if (!active) return;
      setUserId(uid);
      if (!uid) {
        setLoading(false);
        return;
      }
      const { data } = await supabase
        .from("notification_preferences")
        .select("*")
        .eq("user_id", uid)
        .maybeSingle();
      if (active) {
        if (data) {
          const { user_id: _u, created_at: _c, updated_at: _up, ...rest } = data as NotificationPreferences & {
            user_id: string;
            created_at: string;
            updated_at: string;
          };
          setPrefs({ ...defaultPreferences, ...rest });
        }
        setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const save = useCallback(
    async (next: Partial<NotificationPreferences>) => {
      if (!userId) return;
      const merged = { ...prefs, ...next };
      setPrefs(merged);
      await supabase
        .from("notification_preferences")
        .upsert({ user_id: userId, ...merged }, { onConflict: "user_id" });
    },
    [prefs, userId],
  );

  return { prefs, save, loading, userId };
}
