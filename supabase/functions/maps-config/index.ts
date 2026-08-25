import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

/**
 * Returns publishable map configuration only: a Mapbox `pk.` token (safe for
 * the browser by design) and the public style / default viewport. No private
 * data, so anonymous visitors are allowed — privacy layers (driver signals,
 * nearby drivers) remain authenticated elsewhere.
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const token = Deno.env.get('MAPBOX_PUBLIC_TOKEN') ?? '';
    if (!token) {
      return new Response(
        JSON.stringify({ error: 'map_token_missing', message: 'Map token is not configured.' }),
        { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const { data } = await supabase
      .from('map_provider_settings')
      .select('*')
      .eq('id', 1)
      .maybeSingle();

    return new Response(
      JSON.stringify({
        mapboxToken: token,
        styleUrl: data?.style_url ?? 'mapbox://styles/mapbox/light-v11',
        defaultCenter: { lat: data?.default_lat ?? 9.6412, lng: data?.default_lng ?? -13.5784 },
        defaultZoom: data?.default_zoom ?? 12,
        flags: data?.flags ?? { heatmap: false, surge: false, clustering: true },
        provider: data?.routing_provider ?? 'google',
      }),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=300',
        },
      },
    );
  } catch (_e) {
    return new Response(JSON.stringify({ error: 'maps_config_error', message: 'Map configuration unavailable.' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
