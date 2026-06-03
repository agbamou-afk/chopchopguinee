import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

/**
 * admin-delete-user
 *
 * god_admin / super_admin only. If the target has financial history we refuse
 * hard delete and instead anonymize via admin_anonymize_user. Otherwise we
 * remove the auth user (and the profile via FK cleanup) so the email is
 * reusable for new pilot tests.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "missing_jwt" }, 401);
    }

    // Verify caller is god_admin or super_admin
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: "invalid_jwt" }, 401);
    const callerId = userData.user.id;

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: adminRow } = await admin
      .from("admin_users")
      .select("admin_role,status")
      .eq("user_id", callerId)
      .eq("status", "active")
      .maybeSingle();
    if (!adminRow || !["god_admin", "super_admin"].includes(adminRow.admin_role)) {
      return json({ error: "forbidden" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const target = String(body.target_user_id ?? "");
    const reason = body.reason ? String(body.reason).slice(0, 500) : null;
    const confirm = body.confirm === true;
    if (!target || !confirm) return json({ error: "bad_request" }, 400);
    if (target === callerId) return json({ error: "cannot_delete_self" }, 400);

    const { data: hist, error: histErr } = await admin.rpc("user_has_financial_history", {
      _user_id: target,
    });
    if (histErr) return json({ error: "history_check_failed", detail: histErr.message }, 500);

    if (hist === true) {
      // Anonymize instead of hard delete
      const { error: anonErr } = await admin.rpc("admin_anonymize_user", {
        _target: target,
        _reason: reason,
      });
      if (anonErr) return json({ error: "anonymize_failed", detail: anonErr.message }, 500);
      return json({
        ok: true,
        mode: "anonymized",
        message:
          "Ce compte contient des données financières/opérationnelles. Il a été désactivé/anonymisé plutôt que supprimé.",
      });
    }

    // Hard delete: auth user first, then profile rows (FKs allow)
    const { error: delErr } = await admin.auth.admin.deleteUser(target);
    if (delErr) return json({ error: "auth_delete_failed", detail: delErr.message }, 500);

    // Clean up obvious app-side rows (best-effort, ignore missing tables).
    await admin.from("driver_profiles").delete().eq("user_id", target);
    await admin.from("driver_applications").delete().eq("user_id", target);
    await admin.from("user_pins").delete().eq("user_id", target);
    await admin.from("user_roles").delete().eq("user_id", target);
    await admin.from("profiles").delete().eq("user_id", target);

    await admin.rpc("admin_log_test_delete", {
      _target: target,
      _caller: callerId,
      _reason: reason,
    });

    return json({ ok: true, mode: "hard_deleted", message: "Compte test supprimé. Email réutilisable." });
  } catch (e) {
    return json({ error: "exception", detail: String(e?.message ?? e) }, 500);
  }

  function json(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});