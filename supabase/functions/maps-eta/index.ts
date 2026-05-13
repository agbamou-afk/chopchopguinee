import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { checkMapsRateLimit, logMapsRequest } from '../_shared/maps-rate-limit.ts';

interface LatLng { lat: number; lng: number }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const start = Date.now();
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let userId: string | null = null;
  const authHeader = req.headers.get('Authorization') ?? '';
  if (authHeader) {
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await userClient.auth.getUser();
    userId = user?.id ?? null;
  }

  try {
    const body = await req.json();
    const origins: LatLng[] = body.origins ?? [];
    const destinations: LatLng[] = body.destinations ?? [];
    const mode = body.mode ?? 'driving';
    if (!origins.length || !destinations.length || origins.length > 25 || destinations.length > 25) {
      return new Response(JSON.stringify({ error: 'Invalid origins/destinations' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (userId) {
      const rl = await checkMapsRateLimit(admin, userId, 'eta', 120);
      if (!rl.allowed) {
        return new Response(JSON.stringify({ error: 'Rate limited' }), {
          status: 429,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    const key = Deno.env.get('GOOGLE_MAPS_SERVER_KEY');
    if (!key) throw new Error('GOOGLE_MAPS_SERVER_KEY not configured');
    const travelModeMap: Record<string, string> = {
      driving: 'DRIVE',
      walking: 'WALK',
      bicycling: 'BICYCLE',
      two_wheeler: 'TWO_WHEELER',
    };
    const travelMode = travelModeMap[mode] ?? 'DRIVE';
    const toWp = (p: LatLng) => ({
      waypoint: { location: { latLng: { latitude: p.lat, longitude: p.lng } } },
    });
    const reqBody: any = {
      origins: origins.map(toWp),
      destinations: destinations.map(toWp),
      travelMode,
      languageCode: 'fr',
      regionCode: 'gn',
    };
    if (travelMode === 'DRIVE' || travelMode === 'TWO_WHEELER') {
      reqBody.routingPreference = 'TRAFFIC_AWARE';
    }
    const r = await fetch('https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'originIndex,destinationIndex,duration,distanceMeters,status,condition',
      },
      body: JSON.stringify(reqBody),
    });
    const data = await r.json();
    if (!r.ok || !Array.isArray(data)) {
      await logMapsRequest(admin, {
        user_id: userId, provider: 'google', action: 'eta',
        input: body, status: 'error',
        error_message: data?.error?.message ?? data?.[0]?.error?.message ?? 'ERROR',
        latency_ms: Date.now() - start,
      });
      return new Response(JSON.stringify({ error: data?.error?.status ?? 'ERROR', details: data?.error?.message }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const parseDur = (d: string | undefined) =>
      d ? parseInt(String(d).replace('s', ''), 10) || 0 : 0;
    const rows: any[][] = Array.from({ length: origins.length }, () =>
      Array.from({ length: destinations.length }, () => ({
        status: 'ZERO_RESULTS', distanceM: null, durationS: null,
      })),
    );
    for (const el of data) {
      const oi = el.originIndex ?? 0;
      const di = el.destinationIndex ?? 0;
      rows[oi][di] = {
        status: el.condition === 'ROUTE_EXISTS' ? 'OK' : (el.condition ?? 'ZERO_RESULTS'),
        distanceM: el.distanceMeters ?? null,
        durationS: parseDur(el.duration),
      };
    }
    await logMapsRequest(admin, {
      user_id: userId, provider: 'google', action: 'eta',
      input: { o: origins.length, d: destinations.length },
      latency_ms: Date.now() - start,
    });
    return new Response(JSON.stringify({ rows, provider: 'google' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});