import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const token = Deno.env.get('MAPBOX_PUBLIC_TOKEN') ?? '';
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
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});