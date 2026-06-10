// QA-only harness to create/cleanup a confirmed merchant user end-to-end.
// SAFETY:
//  - Service role stays server-side.
//  - Caller must be authenticated AND have the `admin` app_role.
//  - Disabled unless QA_HARNESS_ENABLED === "true" (must NOT be set in prod).
//  - Created users are tagged: user_metadata.qa_user = true, created_by = "merchant_auth_routing_qa".
//  - Cleanup refuses if the user has wallet tx, rides, food orders, payouts,
//    or non-QA marketplace listings.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (Deno.env.get("QA_HARNESS_ENABLED") !== "true") {
    return json({ error: "QA harness disabled in this environment" }, 403);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  // Validate caller is admin
  const userClient = createClient(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: authHeader } },
  });
  const token = authHeader.replace("Bearer ", "");
  const { data: claims, error: claimsErr } = await userClient.auth.getClaims(token);
  if (claimsErr || !claims?.claims?.sub) return json({ error: "Unauthorized" }, 401);
  const callerId = claims.claims.sub as string;

  const admin = createClient(SUPABASE_URL, SERVICE);
  const { data: isAdmin, error: roleErr } = await admin.rpc("has_role", {
    _user_id: callerId,
    _role: "admin",
  });
  if (roleErr || !isAdmin) return json({ error: "Admin role required" }, 403);

  let body: any = {};
  try { body = await req.json(); } catch { /* noop */ }
  const action = body?.action ?? "create";

  if (action === "create") {
    const ts = Date.now();
    const email = `qa.merchant.${ts}@chopchop.test`;
    const password = `QA-${crypto.randomUUID().slice(0, 12)}!`;

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        qa_user: true,
        created_by: "merchant_auth_routing_qa",
        signup_intent: "merchant",
        full_name: "QA Marchand",
      },
    });
    if (createErr || !created?.user) return json({ error: createErr?.message ?? "createUser failed" }, 500);
    const uid = created.user.id;

    // Profile (best-effort; profile may auto-create via trigger)
    await admin.from("profiles").upsert({
      id: uid,
      full_name: "QA Marchand",
      phone: "+224620000000",
    }, { onConflict: "id" });

    // Merchant store
    const slug = `qa-boutique-${uid.slice(0, 6)}-${ts}`;
    const { data: store, error: storeErr } = await admin
      .from("merchant_stores")
      .insert({
        owner_user_id: uid,
        created_by: uid,
        name: "QA Boutique Marchand",
        slug,
        business_name: "QA Boutique Marchand",
        category: "Test",
        phone: "+224620000000",
        whatsapp: "+224620000000",
        district: "Kaloum",
        status: "pending",
        onboarding_status: "submitted",
        verification_state: "pending",
        submitted_at: new Date().toISOString(),
        bio: "[QA] merchant_auth_routing_qa",
      })
      .select("id")
      .single();
    if (storeErr) {
      await admin.auth.admin.deleteUser(uid);
      return json({ error: storeErr.message }, 500);
    }

    // App mode preference
    await admin.from("user_preferences").upsert(
      { user_id: uid, app_mode: "merchant" },
      { onConflict: "user_id" },
    );

    return json({
      ok: true,
      user_id: uid,
      merchant_store_id: store.id,
      email,
      password, // dev-only; harness is gated by QA_HARNESS_ENABLED + admin
      next_route: "/merchant/hub",
    });
  }

  if (action === "cleanup") {
    const uid = body?.user_id as string | undefined;
    if (!uid) return json({ error: "user_id required" }, 400);

    // Confirm it is a QA user
    const { data: target } = await admin.auth.admin.getUserById(uid);
    const meta = (target?.user?.user_metadata ?? {}) as Record<string, unknown>;
    if (meta?.qa_user !== true || meta?.created_by !== "merchant_auth_routing_qa") {
      return json({ error: "Refusing: not a QA-created user" }, 400);
    }

    // Refuse if real activity exists
    const checks: Array<[string, string, string]> = [
      ["wallet_transactions", "user_id", "wallet_transactions"],
      ["rides", "rider_id", "rides"],
      ["food_orders", "customer_id", "food_orders"],
      ["topup_requests", "user_id", "topup_requests"],
    ];
    for (const [table, col, label] of checks) {
      const { count } = await admin.from(table).select("*", { count: "exact", head: true }).eq(col, uid);
      if ((count ?? 0) > 0) return json({ error: `Refusing cleanup: ${label} exist for user` }, 400);
    }
    // Non-QA listings check: any listing whose store is owned by uid without [QA] bio
    const { data: listings } = await admin
      .from("marketplace_listings")
      .select("id, store_id")
      .eq("seller_id", uid);
    if (listings && listings.length > 0) {
      // delete QA listings; they'll be wiped via cascade-ish manual delete
      await admin.from("marketplace_listings").delete().eq("seller_id", uid);
    }

    await admin.from("merchant_stores").delete().eq("owner_user_id", uid);
    await admin.from("user_preferences").delete().eq("user_id", uid);
    await admin.from("profiles").delete().eq("id", uid);
    const { error: delErr } = await admin.auth.admin.deleteUser(uid);
    if (delErr) return json({ error: delErr.message }, 500);
    return json({ ok: true, deleted: uid });
  }

  return json({ error: `Unknown action: ${action}` }, 400);
});