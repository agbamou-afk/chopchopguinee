import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

/**
 * Creates a phone+password account with `phone_confirm: true` so
 * Supabase does NOT send an SMS confirmation. The client then signs
 * in with phone+password as usual.
 *
 * Public (verify_jwt = false) — but uses the service role internally.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { phone, password, first_name, last_name, full_name, email } = await req.json();
    if (!phone || !password || String(password).length < 8) {
      return new Response(JSON.stringify({ error: "Champs invalides" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    const { data, error } = await admin.auth.admin.createUser({
      phone,
      password,
      phone_confirm: true,
      email: email || undefined,
      email_confirm: email ? true : undefined,
      user_metadata: { first_name, last_name, full_name, email: email || null },
    });

    if (error) {
      const status = /already|exists|registered/i.test(error.message) ? 409 : 400;
      return new Response(JSON.stringify({ error: error.message }),
        { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ user_id: data.user?.id ?? null }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});