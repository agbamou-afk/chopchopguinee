import { supabase } from '@/integrations/supabase/client';

export type LocationSearchContext =
  | 'pickup' | 'dropoff' | 'vendor_discovery' | 'search' | 'correction_later';

export interface LocationSearchEventInput {
  query: string;
  context: LocationSearchContext;
  selected_place_id?: string | null;
  selected_label?: string | null;
  selected_source?: string | null;  // 'gazetteer' | 'nominatim' | 'typed' | …
  district?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  confidence?: string | null;
}

/**
 * Log a discrete location-search event. Never throws — search/picker UI
 * must never break because of telemetry. Logs to `location_search_events`
 * (RLS: caller can only write their own).
 */
export async function logLocationSearchEvent(input: LocationSearchEventInput): Promise<void> {
  try {
    const { data } = await supabase.auth.getUser();
    const user_id = data.user?.id ?? null;
    if (!user_id) return; // anon users can't insert (RLS), skip silently
    await supabase.from('location_search_events').insert({
      user_id,
      query: input.query,
      selected_place_id: input.selected_place_id ?? null,
      selected_label: input.selected_label ?? null,
      selected_source: input.selected_source ?? null,
      district: input.district ?? null,
      latitude: input.latitude ?? null,
      longitude: input.longitude ?? null,
      confidence: input.confidence ?? null,
      context: input.context,
    } as never);
  } catch { /* analytics must never break the app */ }
}