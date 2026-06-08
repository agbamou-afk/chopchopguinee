import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { checkMapsRateLimit, logMapsRequest } from '../_shared/maps-rate-limit.ts';

/**
 * maps-search — server-side place search & reverse geocoding for CHOPCHOP.
 *
 * Provider priority for forward search:
 *   1. Google Places API (New) — places:searchText, biased to Guinea/Conakry.
 *   2. Nominatim (OSM) fallback, country-restricted to GN.
 *
 * Reverse geocoding priority:
 *   1. Google Geocoding API.
 *   2. Nominatim reverse.
 *
 * NEVER exposes the server-side Google key. Requires authenticated caller and
 * a per-user rate limit so a misbehaving client can't drain quota.
 */

interface ForwardBody {
  op: 'search';
  query: string;
  proximity?: { lat: number; lng: number };
  limit?: number;
}
interface ReverseBody {
  op: 'reverse';
  lat: number;
  lng: number;
}
type Body = ForwardBody | ReverseBody;

interface SearchResult {
  id: string;
  label: string;
  secondary_label: string | null;
  lat: number;
  lng: number;
  source: 'google' | 'nominatim';
  category: string | null;
  confidence: 'exact' | 'approximate';
}

const GUINEA_BIAS = {
  rectangle: {
    low: { latitude: 9.40, longitude: -13.85 },
    high: { latitude: 9.85, longitude: -13.30 },
  },
};

function bad(status: number, code: string, message: string) {
  return new Response(JSON.stringify({ error: code, message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function googleSearch(query: string, key: string, proximity?: { lat: number; lng: number }, limit = 8): Promise<SearchResult[]> {
  const body: any = {
    textQuery: query,
    languageCode: 'fr',
    regionCode: 'gn',
    maxResultCount: Math.min(Math.max(limit, 1), 10),
    locationBias: proximity
      ? { circle: { center: { latitude: proximity.lat, longitude: proximity.lng }, radius: 20000 } }
      : GUINEA_BIAS,
  };
  const r = await fetch('https://places.googleapis.com/v1/places:searchText', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': key,
      'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.types',
    },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`google_places_${r.status}`);
  const data = await r.json();
  const places = (data?.places ?? []) as any[];
  return places
    .filter((p) => p?.location?.latitude != null && p?.location?.longitude != null)
    .map<SearchResult>((p) => ({
      id: `g:${p.id}`,
      label: p.displayName?.text ?? p.formattedAddress ?? 'Lieu',
      secondary_label: p.formattedAddress ?? null,
      lat: p.location.latitude,
      lng: p.location.longitude,
      source: 'google',
      category: Array.isArray(p.types) && p.types.length ? p.types[0] : null,
      confidence: 'exact',
    }));
}

async function nominatimSearch(query: string, limit = 8, proximity?: { lat: number; lng: number }): Promise<SearchResult[]> {
  const delta = 0.25;
  const base = proximity ?? { lat: 9.641, lng: -13.578 };
  const viewbox = `${base.lng - delta},${base.lat + delta},${base.lng + delta},${base.lat - delta}`;
  const url = `https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&limit=${limit}&countrycodes=gn&viewbox=${viewbox}&bounded=1&q=${encodeURIComponent(query)}`;
  const r = await fetch(url, { headers: { 'Accept-Language': 'fr', 'User-Agent': 'CHOPCHOP/1.0 (maps-search)' } });
  if (!r.ok) throw new Error(`nominatim_${r.status}`);
  const data = (await r.json()) as any[];
  return data
    .filter((d) => d?.lat && d?.lon)
    .map<SearchResult>((d) => {
      const a = (d.address ?? {}) as Record<string, string>;
      const sub = [a.suburb, a.city_district, a.city, a.town, a.village, a.county].filter(Boolean).slice(0, 2).join(' • ');
      return {
        id: `osm:${d.place_id}`,
        label: d.name || (d.display_name as string).split(',')[0],
        secondary_label: sub || (d.display_name as string).split(',').slice(1, 3).join(', '),
        lat: parseFloat(d.lat),
        lng: parseFloat(d.lon),
        source: 'nominatim',
        category: d.type ?? d.class ?? null,
        confidence: 'approximate',
      };
    });
}

async function googleReverse(lat: number, lng: number, key: string): Promise<{ label: string; secondary_label: string | null } | null> {
  const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&language=fr&region=gn&key=${key}`;
  const r = await fetch(url);
  if (!r.ok) throw new Error(`google_geocode_${r.status}`);
  const data = await r.json();
  const first = data?.results?.[0];
  if (!first?.formatted_address) return null;
  const parts = (first.formatted_address as string).split(',').map((s) => s.trim());
  return {
    label: parts[0] ?? first.formatted_address,
    secondary_label: parts.slice(1, 3).join(', ') || null,
  };
}

async function nominatimReverse(lat: number, lng: number): Promise<{ label: string; secondary_label: string | null } | null> {
  const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=16`;
  const r = await fetch(url, { headers: { 'Accept-Language': 'fr', 'User-Agent': 'CHOPCHOP/1.0 (maps-search)' } });
  if (!r.ok) throw new Error(`nominatim_reverse_${r.status}`);
  const data = await r.json();
  if (!data?.display_name) return null;
  const parts = (data.display_name as string).split(',').map((s: string) => s.trim());
  return { label: parts.slice(0, 2).join(', ') || data.display_name, secondary_label: parts.slice(2, 4).join(', ') || null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const start = Date.now();

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return bad(401, 'unauthorized', 'Authentication required.');
  }
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return bad(401, 'unauthorized', 'Authentication required.');

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return bad(400, 'invalid_body', 'Body must be JSON.');
  }

  // Rate limit: 90 calls / minute / user covers both search and reverse.
  const rl = await checkMapsRateLimit(admin, user.id, 'eta', 90);
  if (!rl.allowed) return bad(429, 'rate_limited', 'Trop de requêtes. Réessayez dans une minute.');

  const key = Deno.env.get('GOOGLE_MAPS_SERVER_KEY') ?? '';

  try {
    if (body.op === 'search') {
      const q = (body.query ?? '').trim();
      if (q.length < 2) {
        return new Response(JSON.stringify({ results: [] }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      const limit = Math.min(Math.max(body.limit ?? 8, 1), 10);
      let results: SearchResult[] = [];
      let provider: 'google' | 'nominatim' | 'none' = 'none';
      let providerError: string | null = null;
      if (key) {
        try {
          results = await googleSearch(q, key, body.proximity, limit);
          provider = 'google';
        } catch (e) {
          providerError = (e as Error).message;
        }
      }
      if (results.length === 0) {
        try {
          results = await nominatimSearch(q, limit, body.proximity);
          provider = 'nominatim';
        } catch (e) {
          providerError = providerError ?? (e as Error).message;
        }
      }
      await logMapsRequest(admin, {
        user_id: user.id, provider, action: 'search',
        input: { q_len: q.length, has_proximity: !!body.proximity },
        output_summary: { count: results.length },
        status: results.length > 0 ? 'ok' : 'error',
        error_message: results.length === 0 ? providerError : null,
        latency_ms: Date.now() - start,
      });
      return new Response(JSON.stringify({ results, provider }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (body.op === 'reverse') {
      const lat = Number(body.lat), lng = Number(body.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
        return bad(400, 'invalid_body', 'lat/lng invalides.');
      }
      let label: { label: string; secondary_label: string | null } | null = null;
      let provider: 'google' | 'nominatim' | 'none' = 'none';
      if (key) {
        try { label = await googleReverse(lat, lng, key); provider = 'google'; } catch {}
      }
      if (!label) {
        try { label = await nominatimReverse(lat, lng); provider = 'nominatim'; } catch {}
      }
      await logMapsRequest(admin, {
        user_id: user.id, provider, action: 'reverse',
        input: { lat, lng },
        output_summary: { has_label: !!label },
        status: label ? 'ok' : 'error',
        latency_ms: Date.now() - start,
      });
      return new Response(JSON.stringify({ result: label, provider }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return bad(400, 'invalid_op', 'op must be "search" or "reverse".');
  } catch (e) {
    return new Response(
      JSON.stringify({ error: 'maps_search_error', message: 'Recherche indisponible. Choisissez le point sur la carte.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});