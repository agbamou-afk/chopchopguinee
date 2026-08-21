import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * account-access-termination-worker
 *
 * Processes public.account_access_terminations. For every pending/failed row it
 * verifies the profile is really closed (account_status = 'deleted'), then uses
 * the supported Supabase auth admin API to ban the auth account and revoke its
 * refresh-token / session posture. Only after the auth operation succeeds does
 * it mark the queue row terminated (via account_access_termination_record).
 *
 * Authority model:
 *  - service_role JWT (autonomous / scheduled invocation), or
 *  - an active god_admin / operations_admin / super_admin caller.
 * It never changes product identity authority; auth state is access enforcement
 * only. It is idempotent and never accepts an arbitrary target that is not
 * already enqueued AND closed.
 *
 * Known boundary: banning + refresh-token revocation stops new tokens and
 * session refresh, but an already-issued access JWT stays cryptographically
 * valid until it expires. The database gate public.auth_uid_active() covers
 * that window for RLS-protected surfaces.
 */

function parseJwtClaims(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;
  try {
    const payload = parts[1]
      .replaceAll("-", "+")
      .replaceAll("_", "/")
      .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    return JSON.parse(atob(payload)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const BAN_DURATION = "876000h"; // ~100 years: closure is not time-boxed

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_ROLE) {
    return json({ error: "server_misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "missing_jwt" }, 401);
  const token = authHeader.slice(7);
  const claims = parseJwtClaims(token);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  let actor = "service_role";
  if (claims?.role !== "service_role") {
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData?.user) return json({ error: "invalid_jwt" }, 401);
    const { data: adminRow } = await admin
      .from("admin_users")
      .select("admin_role,status")
      .eq("user_id", userData.user.id)
      .eq("status", "active")
      .maybeSingle();
    const role = adminRow?.admin_role ?? "";
    if (!["god_admin", "operations_admin", "super_admin"].includes(role)) {
      return json({ error: "forbidden" }, 403);
    }
    actor = `admin:${role}`;
  }

  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body?.limit ?? 50) || 50, 1), 200);

  const { data: rows, error: qErr } = await admin
    .from("account_access_terminations")
    .select("user_id,status,attempts")
    .in("status", ["pending", "failed"])
    .lt("attempts", 10)
    .order("requested_at", { ascending: true })
    .limit(limit);
  if (qErr) return json({ error: "queue_read_failed", detail: qErr.message }, 500);

  const results: Array<Record<string, unknown>> = [];

  for (const row of rows ?? []) {
    const target = row.user_id as string;

    // 1. Never act on an account that is not canonically closed.
    const { data: prof } = await admin
      .from("profiles")
      .select("account_status")
      .eq("user_id", target)
      .maybeSingle();
    if (prof?.account_status !== "deleted") {
      await admin.rpc("account_access_termination_record", {
        _target: target,
        _ok: false,
        _error: "ACCOUNT_NOT_CLOSED",
      });
      results.push({ user_id: target, ok: false, error: "ACCOUNT_NOT_CLOSED" });
      continue;
    }

    // 2. Ban the auth account (supported admin API, idempotent).
    let authError: string | null = null;
    const { error: banErr } = await admin.auth.admin.updateUserById(target, {
      ban_duration: BAN_DURATION,
    });
    if (banErr) {
      // A missing auth user means access is already impossible; treat as done.
      if ((banErr as { status?: number }).status === 404) {
        authError = null;
      } else {
        authError = `BAN_FAILED:${banErr.message}`.slice(0, 300);
      }
    }

    // 3. Revoke sessions / refresh tokens globally where supported.
    let sessionsRevoked: boolean | null = null;
    if (!authError) {
      try {
        const res = await fetch(
          `${SUPABASE_URL}/auth/v1/admin/users/${target}/sessions`,
          {
            method: "DELETE",
            headers: {
              apikey: SERVICE_ROLE,
              Authorization: `Bearer ${SERVICE_ROLE}`,
            },
          },
        );
        await res.text();
        sessionsRevoked = res.ok ? true : res.status === 404 ? null : false;
        if (sessionsRevoked === false) {
          authError = `SESSION_REVOKE_FAILED:${res.status}`;
        }
      } catch (e) {
        authError = `SESSION_REVOKE_ERROR:${String(e).slice(0, 200)}`;
      }
    }

    // 4. Only now record the queue outcome.
    const { data: rec, error: recErr } = await admin.rpc(
      "account_access_termination_record",
      { _target: target, _ok: authError === null, _error: authError },
    );
    results.push({
      user_id: target,
      ok: authError === null,
      sessions_revoked: sessionsRevoked,
      error: authError,
      recorded: recErr ? false : ((rec as { ok?: boolean })?.ok ?? null),
    });
  }

  return json({
    ok: true,
    actor,
    processed: results.length,
    terminated: results.filter((r) => r.ok).length,
    failed: results.filter((r) => !r.ok).length,
    results,
  });
});
