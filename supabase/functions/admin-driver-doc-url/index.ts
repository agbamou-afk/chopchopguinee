import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json({ error: "unauthorized" }, 401);
    }
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u } = await userClient.auth.getUser();
    if (!u?.user) return json({ error: "unauthorized" }, 401);

    const admin = createClient(url, service);
    const { data: isOps, error: opsErr } = await admin.rpc("can_manage_operations", { _user_id: u.user.id });
    if (opsErr || !isOps) return json({ error: "forbidden" }, 403);

    const body = await req.json().catch(() => ({}));
    const path = typeof body?.path === "string" ? body.path.trim() : "";
    if (!path || path.includes("..")) return json({ error: "invalid path" }, 400);

    const { data: signed, error: sErr } = await admin.storage
      .from("driver-docs")
      .createSignedUrl(path, 600);
    if (sErr || !signed) return json({ error: "sign failed" }, 500);

    return json({ url: signed.signedUrl, expires_in: 600 });
  } catch (_e) {
    return json({ error: "internal" }, 500);
  }
});

function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}