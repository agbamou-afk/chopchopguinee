import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';

/**
 * Diagnostic-only probe: reports whether MAPBOX_PUBLIC_TOKEN is present and
 * accepted by Mapbox. Never returns the token itself.
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const token = Deno.env.get('MAPBOX_PUBLIC_TOKEN') ?? '';
  if (!token) {
    return new Response(JSON.stringify({ present: false, valid: false, reason: 'missing_secret' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  let status = 0;
  let reason = '';
  try {
    const r = await fetch(
      `https://api.mapbox.com/styles/v1/mapbox/light-v11?access_token=${encodeURIComponent(token)}`,
    );
    status = r.status;
    if (!r.ok) reason = (await r.text()).slice(0, 200);
  } catch (e) {
    reason = String((e as Error)?.message ?? e).slice(0, 200);
  }
  return new Response(
    JSON.stringify({
      present: true,
      prefix: token.slice(0, 3),
      length: token.length,
      style_status: status,
      valid: status === 200,
      reason,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
});
