import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * admin-create-staff-user
 *
 * God Admin only. Provisions a brand-new staff account end-to-end:
 *   1) creates the auth user with a temporary password
 *   2) upserts profile (display name + phone)
 *   3) inserts admin_users row with admin_role + must_change_password=true
 *   4) inserts a parallel user_roles row for the unified role system
 *   5) writes an audit_logs entry
 *
 * Forbidden: creating another god_admin/super_admin via this endpoint.
 * The temporary password is returned exactly once and never persisted.
 */

type StaffRole = "ops_admin" | "finance_admin";

const ALLOWED_ROLES: ReadonlyArray<StaffRole> = ["ops_admin", "finance_admin"];
const ROLE_TO_APP_ROLE: Record<StaffRole, string> = {
  ops_admin: "operations_admin",
  finance_admin: "finance_admin",
};

const DEFAULT_TEMP_PASSWORD = "Welcome%2026";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

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
      return json(
        { error: "server_misconfigured", message: "Configuration serveur manquante." },
        500,
      );
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "missing_jwt", message: "Session expirée. Reconnectez-vous." }, 401);
    }

    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return json({ error: "invalid_jwt", message: "Session invalide." }, 401);
    }
    const callerId = userData.user.id;

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Caller must be god_admin (unified) OR super_admin (legacy admin_users tier).
    const { data: callerAdmin } = await admin
      .from("admin_users")
      .select("admin_role,status")
      .eq("user_id", callerId)
      .eq("status", "active")
      .maybeSingle();
    const { data: callerRoles } = await admin
      .from("user_roles")
      .select("role")
      .eq("user_id", callerId);
    const callerIsGod =
      (callerAdmin?.admin_role === "super_admin") ||
      (Array.isArray(callerRoles) && callerRoles.some((r: { role: string }) => r.role === "god_admin"));
    if (!callerIsGod) {
      return json(
        { error: "forbidden", message: "Accès refusé : réservé au God Admin." },
        403,
      );
    }

    const body = await req.json().catch(() => ({}));
    const username = String(body.username ?? "").trim();
    const displayName = String(body.display_name ?? username ?? "").trim();
    const email = String(body.email ?? "").trim().toLowerCase();
    const phoneRaw = body.phone ? String(body.phone).trim() : "";
    const role = String(body.role ?? "") as StaffRole;
    const tempPassword = String(body.temporary_password ?? DEFAULT_TEMP_PASSWORD);
    const mustChange = body.require_password_change !== false;

    if (!username || username.length < 3 || username.length > 64) {
      return json({ error: "bad_username", message: "Nom d'utilisateur invalide (3-64 caractères)." }, 400);
    }
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ error: "bad_email", message: "Email valide requis." }, 400);
    }
    if (!ALLOWED_ROLES.includes(role)) {
      return json(
        { error: "bad_role", message: "Rôle interdit. Création de God Admin refusée." },
        400,
      );
    }
    if (tempPassword.length < 8) {
      return json({ error: "bad_password", message: "Mot de passe temporaire trop court." }, 400);
    }

    // Create auth user with temp password, pre-confirm email so they can login immediately.
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: {
        full_name: displayName || username,
        username,
        phone: phoneRaw || null,
        provisioned_by: callerId,
        provisioned_at: new Date().toISOString(),
      },
    });
    if (createErr || !created?.user) {
      const msg = /already.*registered|exists/i.test(createErr?.message ?? "")
        ? "Un compte avec cet email existe déjà."
        : (createErr?.message ?? "Création du compte impossible.");
      return json({ error: "auth_create_failed", message: msg }, 400);
    }
    const newUserId = created.user.id;

    // Upsert profile (handle_new_user trigger likely created a base row).
    const { error: profErr } = await admin
      .from("profiles")
      .upsert(
        {
          user_id: newUserId,
          full_name: displayName || username,
          phone: phoneRaw || null,
        },
        { onConflict: "user_id" },
      );
    if (profErr) {
      console.warn("[admin-create-staff-user] profile upsert failed", profErr.message);
    }

    // Insert admin_users row.
    const { error: adminErr } = await admin.from("admin_users").insert({
      user_id: newUserId,
      admin_role: role,
      status: "active",
      created_by: callerId,
      must_change_password: mustChange,
      created_via: "admin-create-staff-user",
      notes: `Provisioned via God Admin UI (${username})`,
    });
    if (adminErr) {
      // Rollback: delete the freshly-created auth user so we don't leave a half-provisioned record.
      await admin.auth.admin.deleteUser(newUserId, false).catch(() => {});
      return json(
        { error: "admin_insert_failed", message: adminErr.message },
        500,
      );
    }

    // Unified role system: insert the matching app_role.
    const appRole = ROLE_TO_APP_ROLE[role];
    const { error: roleErr } = await admin.from("user_roles").insert({
      user_id: newUserId,
      role: appRole,
    });
    if (roleErr && !/duplicate|unique/i.test(roleErr.message)) {
      console.warn("[admin-create-staff-user] user_roles insert failed", roleErr.message);
    }

    // Audit log — never log the password.
    await admin.from("audit_logs").insert({
      actor_id: callerId,
      module: "admins",
      action: "staff.create",
      target_type: "user",
      target_id: newUserId,
      after: {
        admin_role: role,
        app_role: appRole,
        username,
        email_domain: email.split("@")[1] ?? null,
        must_change_password: mustChange,
      },
    }).catch((e) => console.warn("[admin-create-staff-user] audit insert failed", e));

    return json({
      ok: true,
      user_id: newUserId,
      username,
      email,
      admin_role: role,
      app_role: appRole,
      temporary_password: tempPassword,
      must_change_password: mustChange,
      message:
        "Compte créé. Communiquez le mot de passe temporaire en mains propres. L'utilisateur devra le changer à la première connexion.",
    });
  } catch (e) {
    console.error("[admin-create-staff-user] unhandled exception", e);
    return json(
      { error: "exception", message: "Erreur interne." },
      500,
    );
  }
});