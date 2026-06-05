import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed", message: "Méthode non autorisée." }, 405);
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const ANON = Deno.env.get("SUPABASE_ANON_KEY");
    if (!SUPABASE_URL || !SERVICE_ROLE || !ANON) {
      console.error("[admin-delete-user] missing env", {
        hasUrl: !!SUPABASE_URL,
        hasService: !!SERVICE_ROLE,
        hasAnon: !!ANON,
      });
      return json(
        { error: "server_misconfigured", message: "Configuration serveur manquante pour la suppression des comptes." },
        500,
      );
    }
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "missing_jwt", message: "Session expirée. Reconnectez-vous." }, 401);
    }

    // Verify caller is god_admin or super_admin
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return json({ error: "invalid_jwt", message: "Session invalide." }, 401);
    }
    const callerId = userData.user.id;

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: adminRow, error: adminErr } = await admin
      .from("admin_users")
      .select("admin_role,status")
      .eq("user_id", callerId)
      .eq("status", "active")
      .maybeSingle();
    if (adminErr) {
      console.error("[admin-delete-user] admin_users lookup failed", adminErr);
      return json({ error: "admin_lookup_failed", message: "Impossible de vérifier vos droits administrateur." }, 500);
    }
    if (!adminRow || !["god_admin", "super_admin"].includes(adminRow.admin_role)) {
      return json(
        { error: "forbidden", message: "Accès refusé : seul un god_admin peut supprimer un compte test." },
        403,
      );
    }

    const body = await req.json().catch(() => ({}));
    const target = String(body.target_user_id ?? "");
    const reason = body.reason ? String(body.reason).slice(0, 500) : null;
    const confirm = body.confirm === true;
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!target || !uuidRe.test(target) || !confirm) {
      return json({ error: "bad_request", message: "Requête invalide : identifiant cible manquant." }, 400);
    }
    if (target === callerId) {
      return json({ error: "cannot_delete_self", message: "Vous ne pouvez pas supprimer votre propre compte ici." }, 400);
    }

    const { data: hist, error: histErr } = await admin.rpc("user_has_financial_history", {
      _user_id: target,
    });
    if (histErr) {
      console.error("[admin-delete-user] history check failed", histErr);
      return json(
        { error: "history_check_failed", message: "Impossible de vérifier l'historique du compte." },
        500,
      );
    }

    if (hist === true) {
      // Anonymize instead of hard delete
      const { data: anonData, error: anonErr } = await admin.rpc("admin_anonymize_user", {
        _target: target,
        _reason: reason,
      });
      if (anonErr) {
        console.error("[admin-delete-user] anonymize failed", anonErr);
        return json(
          {
            error: "anonymize_failed",
            message: "Impossible d'anonymiser ce compte pour le moment.",
            detail: anonErr.message ?? null,
            code: (anonErr as { code?: string }).code ?? null,
            hint: (anonErr as { hint?: string }).hint ?? null,
          },
          500,
        );
      }
      const a = (anonData ?? {}) as { ok?: boolean; sqlstate?: string; detail?: string; steps?: unknown };
      if (a && a.ok === false) {
        console.error("[admin-delete-user] anonymize returned ok=false", a);
        return json(
          {
            error: "anonymize_failed",
            message: "Impossible d'anonymiser ce compte pour le moment.",
            detail: a.detail ?? null,
            sqlstate: a.sqlstate ?? null,
          },
          500,
        );
      }
      return json({
        ok: true,
        mode: "anonymized",
        steps: a.steps ?? null,
        message:
          "Ce compte contient des données financières. Il a été anonymisé plutôt que supprimé.",
      });
    }

    // Hard delete: auth user first, then profile rows (FKs allow)
    const { error: delErr } = await admin.auth.admin.deleteUser(target);
    if (delErr) {
      console.error("[admin-delete-user] auth delete failed", delErr);
      const msg = /not.?found/i.test(delErr.message ?? "")
        ? "Suppression impossible : utilisateur introuvable."
        : "Impossible de supprimer ce compte pour le moment.";
      return json({ error: "auth_delete_failed", message: msg }, 500);
    }

    // Clean up obvious app-side rows (best-effort, ignore missing tables).
    for (const table of ["driver_profiles", "driver_applications", "user_pins", "user_roles", "profiles"]) {
      const { error: cleanupErr } = await admin.from(table).delete().eq("user_id", target);
      if (cleanupErr) console.warn(`[admin-delete-user] cleanup ${table} failed`, cleanupErr.message);
    }

    const { error: logErr } = await admin.rpc("admin_log_test_delete", {
      _target: target,
      _caller: callerId,
      _reason: reason,
    });
    if (logErr) console.warn("[admin-delete-user] audit log failed", logErr.message);

    return json({
      ok: true,
      mode: "hard_deleted",
      message: "Compte test supprimé. L'email peut être réutilisé.",
    });
  } catch (e) {
    console.error("[admin-delete-user] unhandled exception", e);
    return json(
      { error: "exception", message: "Erreur interne. Réessayez ou contactez le support." },
      500,
    );
  }

  function json(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});