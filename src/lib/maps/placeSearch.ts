import { supabase } from "@/integrations/supabase/client";

export interface PlaceSearchResult {
  id: string;
  label: string;
  secondary_label: string | null;
  lat: number;
  lng: number;
  source: 'google' | 'nominatim';
  category: string | null;
  confidence: 'exact' | 'approximate';
}

export interface ReverseGeocodeResult {
  label: string;
  secondary_label: string | null;
}

/**
 * Forward place search via the maps-search edge function.
 * Returns [] when query is too short or provider fails — callers must show
 * the manual-map-pin fallback in that case.
 */
export async function searchPlaces(
  query: string,
  opts: { proximity?: { lat: number; lng: number }; limit?: number; signal?: AbortSignal } = {},
): Promise<{ results: PlaceSearchResult[]; provider: string }> {
  const q = query.trim();
  if (q.length < 2) return { results: [], provider: 'none' };
  try {
    const { data, error } = await supabase.functions.invoke('maps-search', {
      body: { op: 'search', query: q, proximity: opts.proximity, limit: opts.limit ?? 8 },
    });
    if (error) throw error;
    return { results: (data?.results ?? []) as PlaceSearchResult[], provider: data?.provider ?? 'none' };
  } catch {
    return { results: [], provider: 'error' };
  }
}

/** Reverse geocode via the maps-search edge function. Never throws. */
export async function reverseGeocode(lat: number, lng: number): Promise<ReverseGeocodeResult | null> {
  try {
    const { data, error } = await supabase.functions.invoke('maps-search', {
      body: { op: 'reverse', lat, lng },
    });
    if (error) return null;
    return (data?.result ?? null) as ReverseGeocodeResult | null;
  } catch {
    return null;
  }
}