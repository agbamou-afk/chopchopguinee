import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * admin-staff-lifecycle (G3)
 *
 * Canonical Auth-side half of the staff account lifecycle saga. The database
 * owns authority (`admin_staff_lifecycle_begin_as` → `admin_staff_record_auth_as`
 * → `admin_staff_finalize_*`); this function owns ONLY the Auth identity
 * operations that Postgres cannot perform.
 *
 * Law:
 *  - Only `operations_admin` / `finance_admin` classes. God creation impossible.
 *  - Four-eyes + quorum + idempotency are enforced in the DB, never here.
 *  - Temporary passwords are generated server-side, handed to the Auth API only,
 *    returned exactly once, and never written to any table, audit row or log.
 *  - DB authority finalization happens only after the Auth identity is recorded.
 *  - Every outcome is a machine-readable code returned with HTTP 200 so the UI
 *    never has to surface "Edge Function returned a non-2xx status code".
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Action = "CREATE" | "DEACTIVATE" | "REACTIVATE" | "ROLE_CHANGE" | "ACCESS_RESET";
const ACTIONS: readonly Action[] = ["CREATE", "DEACTIVATE", "REACTIVATE", "ROLE_CHANGE", "ACCESS_RESET"];
const CLASSES = ["operations_admin", "finance_admin"] as const;

function json(body: unknown) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
const ok = (result: string, extra: Record<string, unknown> = {}) =>
  json({ ok: true, result, ...extra });
const fail = (result: string, message: string, extra: Record<string, unknown> = {}) =>
  json({ ok: false, result, message, ...extra });

/** Map a Postgres lifecycle exception onto the canonical outcome contract. */
export function mapDbError(message: string): { code: string; message: string } {
  const m = message ?? "";
  const has = (s: string) => m.toUpperCase().includes(s);
  if (has("APPROVER_QUORUM_UNAVAILABLE")) {
    return {
      code: "APPROVER_QUORUM_UNAVAILABLE",
      message: "Quorum d’approbation indisponible — un deuxième God Admin actif est requis.",
    };
  }
  if (has("IDEMPOTENCY_INTENT_MISMATCH")) {
    return {
      code: "IDEMPOTENCY_INTENT_MISMATCH",
      message: "Cette clé d’opération a déjà été utilisée avec des informations différentes.",
    };
  }
  if (has("APPROVAL_REQUIRED") || has("APPROVAL_INVALID") || has("APPROVAL")) {
    return {
      code: "PENDING_APPROVAL",
      message: "Double validation requise : un second God Admin doit approuver cette opération.",
    };
  }
  if (has("FAILED_FINAL")) {
    return { code: "FAILED_FINAL", message: "Opération définitivement échouée. Utilisez une nouvelle demande." };
  }
  if (has("GOD_TARGET_FORBIDDEN")) {
    return { code: "TARGET_CONFLICT", message: "Un compte God Admin ne peut pas être ciblé." };
  }
  if (has("SELF_LIFECYCLE_FORBIDDEN")) {
    return { code: "TARGET_CONFLICT", message: "Vous ne pouvez pas exécuter cette action sur votre propre compte." };
  }
  if (has("ROLE_FORBIDDEN")) {
    return { code: "TARGET_CONFLICT", message: "Rôle interdit : seuls Operations Admin et Finance Admin sont possibles." };
  }
  if (has("TARGET_NOT_ACTIVE_STAFF")) {
    return { code: "TARGET_CONFLICT", message: "Le compte visé n’est pas un compte staff actif." };
  }
  if (has("READINESS_DENIED")) {
    return { code: "FORBIDDEN", message: "Terminez d’abord le changement de votre mot de passe." };
  }
  if (has("CAPABILITY_DENIED") || has("NOT_AUTHENTICATED") || has("42501")) {
    return { code: "FORBIDDEN", message: "Accès refusé : opération réservée au God Admin." };
  }
  return { code: "FAILED_RETRYABLE", message: m || "Échec temporaire. Réessayez." };
}

/** Cryptographically random temporary password. Never persisted. */
function makeTempPassword(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let out = "";
  for (const b of bytes) out += alphabet[b % alphabet.length];
  return `Cc!${out}9`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("FAILED_FINAL", "Méthode non autorisée.");

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const ANON = Deno.env.get("SUPABASE_ANON_KEY");
  if (!SUPABASE_URL || !SERVICE_ROLE || !ANON) {
    return fail("FAILED_RETRYABLE", "Configuration serveur manquante.");
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return fail("FORBIDDEN", "Session expirée. Reconnectez-vous.");

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  /** GoTrue admin REST helpers (supabase-js exposes no email lookup / logout). */
  const gotrue = async (path: string, init: RequestInit = {}) =>
    await fetch(`${SUPABASE_URL}/auth/v1/admin${path}`, {
      ...init,
      headers: {
        apikey: SERVICE_ROLE,
        Authorization: `Bearer ${SERVICE_ROLE}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    });

  const findAuthUserByEmail = async (email: string) => {
    try {
      const res = await gotrue(`/users?filter=${encodeURIComponent(email)}&per_page=50`);
      if (!res.ok) return null;
      const body = await res.json().catch(() => null) as { users?: Array<Record<string, unknown>> } | null;
      const list = body?.users ?? [];
      return list.find((u) => String(u.email ?? "").toLowerCase() === email) ?? null;
    } catch {
      return null;
    }
  };

  /** Best effort — GoTrue may not expose per-user logout. Readiness already denies capability. */
  const revokeSessions = async (userId: string) => {
    try {
      const res = await gotrue(`/users/${userId}/logout`, { method: "POST" });
      return res.ok;
    } catch {
      return false;
    }
  };

  try {
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return fail("FORBIDDEN", "Session invalide.");
    const callerId = userData.user.id;

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = String(body.action ?? "") as Action;
    if (!ACTIONS.includes(action)) return fail("FAILED_FINAL", "Action inconnue.");

    const idempotencyKey = String(body.idempotency_key ?? "").trim();
    if (idempotencyKey.length < 8) return fail("FAILED_FINAL", "Clé d’opération invalide.");

    const email = String(body.email ?? "").trim().toLowerCase();
    const username = String(body.username ?? "").trim();
    const displayName = String(body.display_name ?? "").trim() || username;
    const phone = body.phone ? String(body.phone).trim() : "";
    const role = body.role ? String(body.role) : null;
    const targetUserId = body.target_user_id ? String(body.target_user_id) : null;
    const approvalId = body.approval_id ? String(body.approval_id) : null;
    const reason = body.reason ? String(body.reason).trim() : null;
    const mustChange = body.must_change_password !== false;

    if (action === "CREATE") {
      if (!username || username.length < 3 || username.length > 64) {
        return fail("FAILED_FINAL", "Nom d’utilisateur invalide (3 à 64 caractères).");
      }
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return fail("FAILED_FINAL", "Email de connexion valide requis.");
      }
    } else if (!targetUserId) {
      return fail("FAILED_FINAL", "Compte cible requis.");
    }
    if (["CREATE", "REACTIVATE", "ROLE_CHANGE"].includes(action)) {
      if (!role || !(CLASSES as readonly string[]).includes(role)) {
        return fail("TARGET_CONFLICT", "Rôle interdit : seuls Operations Admin et Finance Admin sont possibles.");
      }
    }

    // Caller must be a lifecycle-ready God Admin before anything else happens.
    const { data: readiness } = await admin.rpc("admin_staff_readiness", { _uid: callerId });
    if (readiness === "temp_password_required") {
      return fail("FORBIDDEN", "Terminez d’abord le changement de votre mot de passe.");
    }

    const targetKey = action === "CREATE" ? email : String(targetUserId);

    // 1) Governed begin: capability + four-eyes + quorum + idempotency, all server-side.
    const { data: begun, error: beginErr } = await admin.rpc("admin_staff_lifecycle_begin_as", {
      _caller: callerId,
      _action: action,
      _idempotency_key: idempotencyKey,
      _target_key: targetKey,
      _target_role: role,
      _must_change: mustChange,
      _approval_id: approvalId,
      _target_user_id: targetUserId,
      _reason: reason,
    });
    if (beginErr) {
      const mapped = mapDbError(beginErr.message ?? "");
      return fail(mapped.code, mapped.message);
    }
    const saga = begun as {
      result: string; request_id?: string; state?: string;
      auth_user_id?: string | null; target_user_id?: string | null;
    };
    if (saga.result === "ALREADY_COMPLETED") {
      return ok("ALREADY_COMPLETED", { user_id: saga.target_user_id ?? saga.auth_user_id ?? null });
    }
    const requestId = saga.request_id!;

    const abort = async (code: string, message: string, final = false) => {
      await admin.rpc("admin_staff_fail_as", { _request_id: requestId, _error_code: code, _final: final });
      return fail(final ? "FAILED_FINAL" : "FAILED_RETRYABLE", message, { lifecycle_code: code });
    };

    if (action === "CREATE") {
      // 2) Resolve or provision the Auth identity — exactly one per lifecycle request.
      let authUserId = saga.auth_user_id ?? null;
      let tempPassword: string | null = null;

      if (!authUserId) {
        const existing = await findAuthUserByEmail(email);
        if (existing) {
          const meta = (existing.user_metadata ?? {}) as Record<string, unknown>;
          if (meta.staff_lifecycle_request_id === requestId) {
            // A previous attempt created this identity but timed out before recording it.
            authUserId = String(existing.id);
          } else {
            await admin.rpc("admin_staff_fail_as", {
              _request_id: requestId, _error_code: "ACCOUNT_ALREADY_EXISTS", _final: true,
            });
            return fail("ACCOUNT_ALREADY_EXISTS",
              "Un compte existe déjà avec cet email. Aucune autorité staff ne lui a été accordée.");
          }
        }
      }

      if (!authUserId) {
        tempPassword = makeTempPassword();
        const { data: created, error: createErr } = await admin.auth.admin.createUser({
          email,
          password: tempPassword,
          email_confirm: true,
          user_metadata: {
            full_name: displayName || username,
            username,
            phone: phone || null,
            staff_lifecycle_request_id: requestId,
          },
        });
        if (createErr || !created?.user) {
          const raw = createErr?.message ?? "";
          if (/already.*registered|exists|duplicate/i.test(raw)) {
            const late = await findAuthUserByEmail(email);
            const meta = (late?.user_metadata ?? {}) as Record<string, unknown>;
            if (late && meta.staff_lifecycle_request_id === requestId) {
              authUserId = String(late.id);
            } else {
              await admin.rpc("admin_staff_fail_as", {
                _request_id: requestId, _error_code: "ACCOUNT_ALREADY_EXISTS", _final: true,
              });
              return fail("ACCOUNT_ALREADY_EXISTS",
                "Un compte existe déjà avec cet email. Aucune autorité staff ne lui a été accordée.");
            }
          } else {
            return await abort("AUTH_CREATE_FAILED", raw || "Création du compte impossible.");
          }
        } else {
          authUserId = created.user.id;
        }
      }

      // 3) Record the Auth identity BEFORE any authority is written.
      const { error: recErr } = await admin.rpc("admin_staff_record_auth_as", {
        _request_id: requestId, _auth_user_id: authUserId,
      });
      if (recErr) return await abort("AUTH_RECORD_FAILED", "Identité créée mais non enregistrée. Réessayez la même opération.");

      // 4) Authority finalization. Idempotent: a repeat returns ALREADY_COMPLETED, never a 500.
      const { data: fin, error: finErr } = await admin.rpc("admin_staff_finalize_create_as", {
        _request_id: requestId, _username: username, _display_name: displayName, _phone: phone,
      });
      if (finErr) return await abort("FINALIZE_FAILED", "Compte créé, autorité non finalisée. Relancez la même opération.");

      const result = (fin as { result?: string })?.result ?? "CREATED";
      return ok(result === "ALREADY_COMPLETED" ? "ALREADY_COMPLETED" : "CREATED", {
        user_id: authUserId,
        username,
        email,
        admin_role: role,
        must_change_password: mustChange,
        // Returned exactly once; never stored anywhere.
        temporary_password: tempPassword,
        message: tempPassword
          ? "Compte créé. Communiquez le mot de passe temporaire en mains propres."
          : "Opération reprise : le mot de passe temporaire initial reste valable.",
      });
    }

    if (action === "DEACTIVATE") {
      const { error: finErr } = await admin.rpc("admin_staff_finalize_deactivate_as", { _request_id: requestId });
      if (finErr) {
        const mapped = mapDbError(finErr.message ?? "");
        return await abort(mapped.code, mapped.message, mapped.code === "TARGET_CONFLICT");
      }
      const revoked = await revokeSessions(targetUserId!);
      return ok("DEACTIVATED", { user_id: targetUserId, sessions_revoked: revoked });
    }

    // REACTIVATE / ROLE_CHANGE / ACCESS_RESET all end in an authority finalization.
    let tempPassword: string | null = null;
    if (action === "ACCESS_RESET" || action === "REACTIVATE") {
      tempPassword = makeTempPassword();
      const { error: pwErr } = await admin.auth.admin.updateUserById(targetUserId!, {
        password: tempPassword,
      });
      if (pwErr) return await abort("AUTH_PASSWORD_RESET_FAILED", "Réinitialisation du mot de passe impossible.");
    }

    const { error: authErr } = await admin.rpc("admin_staff_finalize_authority_as", { _request_id: requestId });
    if (authErr) {
      const mapped = mapDbError(authErr.message ?? "");
      return await abort(mapped.code, mapped.message, mapped.code === "TARGET_CONFLICT");
    }
    const revoked = await revokeSessions(targetUserId!);

    return ok(action, {
      user_id: targetUserId,
      admin_role: role,
      sessions_revoked: revoked,
      temporary_password: tempPassword,
      message: tempPassword
        ? "Accès réinitialisé. Communiquez le mot de passe temporaire en mains propres."
        : "Opération effectuée.",
    });
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    console.error("[admin-staff-lifecycle] unhandled", detail);
    const mapped = mapDbError(detail);
    return fail(mapped.code, mapped.message);
  }
});
