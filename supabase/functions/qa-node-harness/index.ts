// Read-only QA evidence runner.
// Replaces the old practice of shipping migrations purely to run test harnesses.
// SAFETY:
//  - Only the allowlisted, self-rolling-back `_qa_*` harnesses can be invoked.
//  - Caller must present either the service role key or an `admin` user JWT.
//  - The harnesses themselves roll back every fixture they create.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED = new Set([
  "_qa_node0_course",
  "_qa_node1_bonbonna",
  "_qa_node1_bonbonna_sweeper",
  "_qa_node1_bonbonna_matrix",
  "_qa_node1_bonbonna_full",
  "_qa_node2_taxi_full",
  "_qa_s13_run1",
  "_qa_s13_run2",
  "_qa_s13_run3",
  "_qa_s13_run4",
  "_qa_s13_run5",
  "_qa_s13_run6",
  "_qa_s13_run7",
  "_qa_node3_repas_r1_r4",
  "_qa_node3_repas_pickup",
  "_qa_node3_repas_r5",
  "_qa_node3_repas_r5_runtime",
  "_qa_node3_repas_r6_custody",
  "_qa_node3_repas_r7_tracking_receipt",
  "_qa_node3_repas_r8_discovery",
  "_qa_node3_repas_r8_channel",
  "_qa_node3_repas_r8_core",
  "_qa_node3_repas_r8_extra",
  "_qa_node3_repas_r8_discovery_truth",
  "_qa_node3_repas_r9_recovery_flows",
  "_qa_node3_repas_r10_operations",
  "_qa_node3_repas_r11_conakry_hardening",
  "_qa_node4_marche_r1",
  "_qa_node4_marche_r15",
  "_qa_node4_marche_r2",
  "_qa_node4_marche_r3",
  "_qa_node4_marche_r35",
  "_qa_node4_marche_r4",
  "_qa_node4_marche_r5",
  "_qa_node4_marche_r6",
  "_qa_node4_marche_r65",
  "_qa_node4_marche_r7",
  "_qa_node4_marche_r8",
  "_qa_node4_marche_r9",
  "_qa_node4_marche_r10",
  "_qa_node4_marche_r11",
]);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const qaToken = (Deno.env.get("QA_NODE_HARNESS_TOKEN") ?? "").trim();
  const presented = (req.headers.get("x-qa-token") ?? "").trim();
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();

  const admin = createClient(SUPABASE_URL, SERVICE);
  let authorized = qaToken.length > 0 && presented === qaToken;
  if (!authorized && !token) return json({ error: "Unauthorized" }, 401);
  authorized = authorized || token === SERVICE;
  if (!authorized) {
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: claims } = await userClient.auth.getClaims(token);
    const callerId = claims?.claims?.sub as string | undefined;
    if (!callerId) return json({ error: "Unauthorized" }, 401);
    const { data: isAdmin } = await admin.rpc("has_role", { _user_id: callerId, _role: "admin" });
    authorized = !!isAdmin;
  }
  if (!authorized) return json({ error: "Admin role required" }, 403);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* noop */ }
  const fn = String(body?.fn ?? "");
  if (!ALLOWED.has(fn)) return json({ error: "Harness not allowlisted", fn }, 400);

  const { data, error } = await admin.rpc(fn as never);
  if (error) return json({ fn, error: error.message }, 500);

  // Harnesses return either a bare assertion array, an object carrying a
  // `results` array, or a pre-summarised { total, failed, failures } object.
  const payload = data as Record<string, unknown> | unknown[] | null;
  if (!Array.isArray(payload) && payload && typeof payload.total === "number" &&
      !Array.isArray(payload.results)) {
    return json({ fn, ...payload });
  }
  const rows = (Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.results)
      ? (payload!.results as unknown[])
      : []) as Record<string, unknown>[];
  const failed = rows.filter((r) => r?.ok !== true);
  return json({
    fn,
    total: rows.length,
    failed: failed.length,
    failures: failed,
  });
});
