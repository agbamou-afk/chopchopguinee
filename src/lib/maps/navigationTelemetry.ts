import { supabase } from "@/integrations/supabase/client";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export interface NavigationEventInput {
  event_name: string;
  surface?: string | null;
  provider?: string | null;
  ride_id?: string | null;
  mission_id?: string | null;
  metadata?: Record<string, unknown>;
}

/**
 * Persist a navigation/map telemetry event in `navigation_events` and mirror it
 * to Analytics so existing dashboards still receive the signal. Never throws —
 * navigation must continue even if logging fails.
 */
export async function logNavigationEvent(input: NavigationEventInput): Promise<void> {
  const { event_name, surface = null, provider = null, ride_id = null, mission_id = null, metadata = {} } = input;
  try { Analytics.track(event_name as any, { metadata: { surface, provider, ride_id, mission_id, ...metadata } }); } catch { /* noop */ }
  try {
    const { data } = await supabase.auth.getUser();
    const user_id = data.user?.id ?? null;
    await supabase.from("navigation_events").insert({
      user_id, event_name, surface, provider, ride_id, mission_id, metadata,
    } as never);
  } catch { /* analytics must never break the app */ }
}
