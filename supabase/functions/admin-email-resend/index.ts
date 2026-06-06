import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * admin-email-resend
 *
 * god_admin / super_admin only. Re-triggers a branded signup confirmation
 * email for an unconfirmed auth user via supabase.auth.resend, which fires
 * the existing auth-email-hook → pgmq → process-email-queue path. No email
 * confirmation is bypassed.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const ANON = Deno.env.get("SUPABASE_ANON_KEY");
    if (!SUPABASE_URL || !SERVICE_ROLE || !ANON) {
      return json({ error: "server_misconfigured" }, 500);
    }
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "missing_jwt" }, 401);

    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: "invalid_jwt" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: adminRow } = await admin
      .from("admin_users")
      .select("admin_role,status")
      .eq("user_id", userData.user.id)
      .eq("status", "active")
      .maybeSingle();
    if (!adminRow || !["god_admin", "super_admin"].includes(adminRow.admin_role)) {
      return json({ error: "forbidden", message: "Réservé aux god_admin." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ error: "invalid_email", message: "Email invalide." }, 400);
    }

    // Use an anon client to call auth.resend — this triggers the auth-email-hook
    // exactly like the in-app "Renvoyer l'email" button.
    const anonClient = createClient(SUPABASE_URL, ANON);
    const origin = req.headers.get("origin") ?? "https://chopchopguinee.com";
    const { error: resendErr } = await anonClient.auth.resend({
      type: "signup",
      email,
      options: { emailRedirectTo: `${origin}/` },
    });

    if (resendErr) {
      console.error("[admin-email-resend] resend failed", resendErr);
      return json(
        {
          error: "resend_failed",
          message: resendErr.message ?? "Échec de l'envoi.",
          code: (resendErr as { status?: number }).status ?? null,
        },
        500,
      );
    }

    return json({
      ok: true,
      email,
      message:
        "Demande de renvoi acceptée. Si l'utilisateur existe et n'est pas confirmé, un email est mis en file.",
    });
  } catch (e) {
    console.error("[admin-email-resend] exception", e);
    return json({ error: "exception", message: (e as Error).message }, 500);
  }

  function json(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});