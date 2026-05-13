import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { checkMapsRateLimit, logMapsRequest } from '../_shared/maps-rate-limit.ts';

interface LatLng { lat: number; lng: number }
interface Body {
  origin: LatLng;
  destination: LatLng;
  mode?: 'driving' | 'walking' | 'bicycling' | 'two_wheeler';
  waypoints?: LatLng[];
}

function validate(body: any): body is Body {
  if (!body || typeof body !== 'object') return false;
  const ok = (p: any) => p && typeof p.lat === 'number' && typeof p.lng === 'number'
    && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;
  return ok(body.origin) && ok(body.destination);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const start = Date.now();

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Identify caller (allow anon; just no rate-limit row keyed for them)
  const authHeader = req.headers.get('Authorization') ?? '';
  let userId: string | null = null;
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
    if (!validate(body)) {
      return new Response(JSON.stringify({ error: 'Invalid body' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (userId) {
      const rl = await checkMapsRateLimit(admin, userId, 'route', 60);
      if (!rl.allowed) {
        return new Response(JSON.stringify({ error: 'Rate limited' }), {
          status: 429,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    const key = Deno.env.get('GOOGLE_MAPS_SERVER_KEY');
    if (!key) throw new Error('GOOGLE_MAPS_SERVER_KEY not configured');

    const mode = body.mode ?? 'driving';
    const params = new URLSearchParams({
      origin: `${body.origin.lat},${body.origin.lng}`,
      destination: `${body.destination.lat},${body.destination.lng}`,
      mode,
      key,
      region: 'gn',
      language: 'fr',
    });
    if (body.waypoints?.length) {
      params.set('waypoints', body.waypoints.map(w => `${w.lat},${w.lng}`).join('|'));
    }

    const r = await fetch(`https://maps.googleapis.com/maps/api/directions/json?${params}`);
    const data = await r.json();

    if (data.status !== 'OK' || !data.routes?.[0]) {
      await logMapsRequest(admin, {
        user_id: userId, provider: 'google', action: 'route',
        input: body, status: 'error',
        error_message: data.status, latency_ms: Date.now() - start,
      });
      return new Response(JSON.stringify({ error: data.status, details: data.error_message }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const route = data.routes[0];
    const leg = route.legs[0];
    const normalized = {
      polyline: route.overview_polyline.points,
      distanceM: route.legs.reduce((s: number, l: any) => s + (l.distance?.value ?? 0), 0),
      durationS: route.legs.reduce((s: number, l: any) => s + (l.duration?.value ?? 0), 0),
      bbox: route.bounds,
      steps: leg.steps.map((s: any) => ({
        instruction: s.html_instructions,
        distanceM: s.distance.value,
        durationS: s.duration.value,
        polyline: s.polyline.points,
        maneuver: s.maneuver ?? null,
        startLocation: s.start_location,
        endLocation: s.end_location,
      })),
      provider: 'google',
    };

    await logMapsRequest(admin, {
      user_id: userId, provider: 'google', action: 'route',
      input: { origin: body.origin, destination: body.destination, mode },
      output_summary: { distanceM: normalized.distanceM, durationS: normalized.durationS },
      latency_ms: Date.now() - start,
    });

    return new Response(JSON.stringify(normalized), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    await logMapsRequest(admin, {
      user_id: userId, provider: 'google', action: 'route',
      input: {}, status: 'error',
      error_message: (e as Error).message, latency_ms: Date.now() - start,
    });
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});