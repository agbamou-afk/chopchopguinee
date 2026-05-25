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

/** Decode a Google encoded polyline (precision 1e5). */
function decodePolyline(str: string): Array<{ lat: number; lng: number }> {
  let index = 0, lat = 0, lng = 0;
  const coords: Array<{ lat: number; lng: number }> = [];
  while (index < str.length) {
    let b: number, shift = 0, result = 0;
    do { b = str.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    const dlat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += dlat;
    shift = 0; result = 0;
    do { b = str.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    const dlng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += dlng;
    coords.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return coords;
}

/** French maneuver dictionary for OSRM fallback. */
const OSRM_FR: Record<string, string> = {
  'depart': 'Départ',
  'continue': 'Continuez tout droit',
  'turn-left': 'Tournez à gauche',
  'turn-right': 'Tournez à droite',
  'turn-slight-left': 'Tournez légèrement à gauche',
  'turn-slight-right': 'Tournez légèrement à droite',
  'slight-left': 'Tournez légèrement à gauche',
  'slight-right': 'Tournez légèrement à droite',
  'sharp-left': 'Tournez franchement à gauche',
  'sharp-right': 'Tournez franchement à droite',
  'turn-sharp-left': 'Tournez franchement à gauche',
  'turn-sharp-right': 'Tournez franchement à droite',
  'uturn': 'Faites demi-tour',
  'roundabout': 'Prenez le rond-point',
  'rotary': 'Prenez le rond-point',
  'roundabout-turn': 'Prenez le rond-point',
  'exit-roundabout': 'Sortez du rond-point',
  'exit-rotary': 'Sortez du rond-point',
  'merge': 'Insérez-vous',
  'fork': 'Restez sur la voie',
  'end-of-road': 'Au bout de la route',
  'new-name': 'Continuez',
  'notification': 'Continuez',
  'arrive': 'Arrivée à destination',
};
function osrmFrenchInstruction(type: string | null | undefined, modifier: string | null | undefined, streetName: string | null | undefined): string {
  const key = type && modifier && type !== 'turn' ? `${type}-${modifier}` : (type ?? '');
  const base = OSRM_FR[key] ?? OSRM_FR[type ?? ''] ?? (modifier ? OSRM_FR[`turn-${modifier}`] ?? 'Continuez' : 'Continuez');
  if (streetName && streetName.trim().length > 0 && type !== 'arrive' && type !== 'depart') {
    return `${base} sur ${streetName}`;
  }
  return base;
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
    const travelModeMap: Record<string, string> = {
      driving: 'DRIVE',
      walking: 'WALK',
      bicycling: 'BICYCLE',
      two_wheeler: 'TWO_WHEELER',
    };
    const travelMode = travelModeMap[mode] ?? 'DRIVE';
    const toWp = (p: LatLng) => ({ location: { latLng: { latitude: p.lat, longitude: p.lng } } });
    const reqBody: any = {
      origin: toWp(body.origin),
      destination: toWp(body.destination),
      travelMode,
      languageCode: 'fr',
      regionCode: 'gn',
      polylineEncoding: 'ENCODED_POLYLINE',
    };
    if (travelMode === 'DRIVE' || travelMode === 'TWO_WHEELER') {
      reqBody.routingPreference = 'TRAFFIC_AWARE';
    }
    if (body.waypoints?.length) {
      reqBody.intermediates = body.waypoints.map(toWp);
    }

    const fieldMask = [
      'routes.duration',
      'routes.distanceMeters',
      'routes.polyline.encodedPolyline',
      'routes.viewport',
      'routes.legs.steps.distanceMeters',
      'routes.legs.steps.staticDuration',
      'routes.legs.steps.polyline.encodedPolyline',
      'routes.legs.steps.navigationInstruction',
      'routes.legs.steps.startLocation',
      'routes.legs.steps.endLocation',
    ].join(',');

    const r = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': fieldMask,
      },
      body: JSON.stringify(reqBody),
    });
    const data = await r.json();

    if (!r.ok || !data.routes?.[0]) {
      // Fallback to public OSRM so the UI keeps working when Google blocks/denies.
      try {
        const profile = travelMode === 'WALK' ? 'foot' : travelMode === 'BICYCLE' ? 'bike' : 'driving';
        const coords = `${body.origin.lng},${body.origin.lat};${body.destination.lng},${body.destination.lat}`;
        const osrmUrl = `https://router.project-osrm.org/route/v1/${profile}/${coords}?overview=full&geometries=polyline&steps=true`;
        const or = await fetch(osrmUrl);
        const od = await or.json();
        const oroute = od?.routes?.[0];
        if (or.ok && oroute) {
          const rawSteps = oroute.legs?.[0]?.steps ?? [];
          // First pass: extract start locations + step polylines
          const stepsBase = rawSteps.map((s: any) => {
            const start = s.maneuver?.location
              ? { lat: s.maneuver.location[1], lng: s.maneuver.location[0] }
              : null;
            const decoded = s.geometry ? decodePolyline(s.geometry) : [];
            return { raw: s, start, decoded };
          });
          // Second pass: derive endLocation from next step start or own polyline tail or destination
          const steps = stepsBase.map((entry: any, i: number) => {
            const next = stepsBase[i + 1];
            const tail = entry.decoded.length > 0 ? entry.decoded[entry.decoded.length - 1] : null;
            const end = next?.start ?? tail ?? (i === stepsBase.length - 1 ? body.destination : entry.start);
            const startLocation = entry.start ?? (entry.decoded[0] ?? null);
            const s = entry.raw;
            const streetName = (s.name && String(s.name).trim().length > 0) ? String(s.name) : null;
            return {
              instruction: osrmFrenchInstruction(s.maneuver?.type, s.maneuver?.modifier, streetName),
              distanceM: Math.round(s.distance ?? 0),
              durationS: Math.round(s.duration ?? 0),
              polyline: s.geometry,
              maneuver: s.maneuver?.type ?? null,
              startLocation,
              endLocation: end,
            };
          });
          // Derive bbox from decoded route polyline
          let derivedBbox: any = null;
          try {
            const pts = decodePolyline(oroute.geometry ?? '');
            if (pts.length > 0) {
              let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
              for (const p of pts) {
                if (p.lat < minLat) minLat = p.lat;
                if (p.lat > maxLat) maxLat = p.lat;
                if (p.lng < minLng) minLng = p.lng;
                if (p.lng > maxLng) maxLng = p.lng;
              }
              derivedBbox = {
                northeast: { lat: maxLat, lng: maxLng },
                southwest: { lat: minLat, lng: minLng },
              };
            }
          } catch { /* tolerate */ }
          const fallback = {
            polyline: oroute.geometry,
            distanceM: Math.round(oroute.distance ?? 0),
            durationS: Math.round(oroute.duration ?? 0),
            bbox: derivedBbox,
            steps,
            // Normalized to match RouteProvider name; was previously 'osrm-fallback'.
            provider: 'osrm',
          };
          await logMapsRequest(admin, {
            user_id: userId, provider: 'osrm', action: 'route',
            input: { origin: body.origin, destination: body.destination, mode },
            output_summary: { distanceM: fallback.distanceM, durationS: fallback.durationS, fallback_reason: data?.error?.status },
            latency_ms: Date.now() - start,
          });
          return new Response(JSON.stringify(fallback), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
      } catch (_) { /* fall through to original error */ }

      await logMapsRequest(admin, {
        user_id: userId, provider: 'google', action: 'route',
        input: body, status: 'error',
        error_message: data?.error?.message ?? 'NO_ROUTE',
        latency_ms: Date.now() - start,
      });
      return new Response(JSON.stringify({ error: data?.error?.status ?? 'NO_ROUTE', details: data?.error?.message }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const route = data.routes[0];
    const parseDur = (d: string | undefined) =>
      d ? parseInt(String(d).replace('s', ''), 10) || 0 : 0;
    const allSteps = (route.legs ?? []).flatMap((l: any) => l.steps ?? []);
    const normalized = {
      polyline: route.polyline?.encodedPolyline,
      distanceM: route.distanceMeters ?? 0,
      durationS: parseDur(route.duration),
      bbox: route.viewport
        ? {
            northeast: { lat: route.viewport.high?.latitude, lng: route.viewport.high?.longitude },
            southwest: { lat: route.viewport.low?.latitude, lng: route.viewport.low?.longitude },
          }
        : null,
      steps: allSteps.map((s: any) => ({
        instruction: s.navigationInstruction?.instructions ?? '',
        distanceM: s.distanceMeters ?? 0,
        durationS: parseDur(s.staticDuration),
        polyline: s.polyline?.encodedPolyline,
        maneuver: s.navigationInstruction?.maneuver ?? null,
        startLocation: s.startLocation?.latLng
          ? { lat: s.startLocation.latLng.latitude, lng: s.startLocation.latLng.longitude }
          : null,
        endLocation: s.endLocation?.latLng
          ? { lat: s.endLocation.latLng.latitude, lng: s.endLocation.latLng.longitude }
          : null,
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