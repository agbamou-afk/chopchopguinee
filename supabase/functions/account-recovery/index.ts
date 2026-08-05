import { createClient } from "npm:@supabase/supabase-js@2";
import {
  EnrollmentPayload,
  generateRecoveryKey,
  keyedHash,
  normalizeAnswer,
  normalizeBirthdate,
  normalizeEmail,
  normalizeRecoveryKey,
  openEnrollment,
  randomToken,
  safeEqual,
  sealEnrollment,
} from "./crypto.ts";
import { QUESTION_IDS, questionLabel, RECOVERY_QUESTIONS } from "./questions.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * account-recovery
 *
 * Fully self-service password recovery. No admin, no support agent, no email
 * link and no OTP is involved at any point. The user proves possession of:
 *   1. their date of birth,
 *   2. two of the three private answers they enrolled (chosen at random), and
 *   3. the one-time CHOPCHOP recovery key (the actual high-entropy secret).
 *
 * Only hashes ever leave this function towards the database, and only generic
 * responses ever leave it towards the browser.
 */

const GENERIC_FAILURE = "Informations de récupération incorrectes ou demande expirée.";
const CHALLENGE_TTL_MS = 15 * 60 * 1000;
const RESET_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const COOLDOWN_MS = 30 * 60 * 1000;
const COOLDOWN_WINDOW_MS = 24 * 60 * 60 * 1000;
const COOLDOWN_THRESHOLD = 3;
const MIN_ANSWER_LENGTH = 3;
const MIN_PASSWORD_LENGTH = 8;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function fail(status = 400) {
  return json({ ok: false, message: GENERIC_FAILURE }, status);
}

/** Guinea MSISDN → `+224XXXXXXXXX`, or "" when it is not a plausible number. */
function normalizeGuineaPhone(raw: string): string {
  const digits = (raw ?? "").replace(/\D/g, "");
  const local = digits.startsWith("224") ? digits.slice(3) : digits;
  if (local.length !== 9 || !local.startsWith("6")) return "";
  return `+224${local}`;
}

/** Pads every public response to a comparable duration to blunt timing oracles. */
async function padTiming(startedAt: number, targetMs = 700) {
  const elapsed = Date.now() - startedAt;
  if (elapsed < targetMs) await new Promise((r) => setTimeout(r, targetMs - elapsed));
}

function pickTwo<T>(items: T[]): T[] {
  const pool = [...items];
  const out: T[] = [];
  while (out.length < 2 && pool.length) {
    const idx = crypto.getRandomValues(new Uint32Array(1))[0] % pool.length;
    out.push(pool.splice(idx, 1)[0]);
  }
  return out;
}

type Admin = ReturnType<typeof createClient>;

async function isPrivilegedAccount(admin: Admin, userId: string): Promise<boolean> {
  const [{ data: staff }, { data: roles }] = await Promise.all([
    admin.from("admin_users").select("user_id").eq("user_id", userId).maybeSingle(),
    admin.from("user_roles").select("role").eq("user_id", userId),
  ]);
  if (staff) return true;
  const privileged = new Set([
    "admin",
    "operations_admin",
    "finance_admin",
    "god_admin",
  ]);
  return Array.isArray(roles) && roles.some((r: { role: string }) => privileged.has(r.role));
}

/** Verifies a password without disturbing the caller's session. */
async function passwordIsValid(
  supabaseUrl: string,
  anonKey: string,
  email: string,
  password: string,
): Promise<boolean> {
  try {
    const res = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/** Revokes every refresh token / device session for the user. */
/**
 * Global sign-out for one user.
 *
 * Verified on this project's GoTrue build (2026-08-05): both admin endpoints
 * below return 404, so neither is available here. Session revocation is
 * instead delivered by the admin password update itself — after `reset`, the
 * pre-reset refresh token is rejected with `refresh_token_not_found`
 * (measured, not assumed). The endpoints are still attempted first so the
 * explicit path is used automatically if the platform later exposes it.
 */
async function revokeAllSessions(
  supabaseUrl: string,
  serviceRole: string,
  userId: string,
): Promise<boolean> {
  const attempts: Array<{ url: string; method: string; body?: string }> = [
    { url: `${supabaseUrl}/auth/v1/admin/users/${userId}/sessions`, method: "DELETE" },
    {
      url: `${supabaseUrl}/auth/v1/admin/users/${userId}/logout`,
      method: "POST",
      body: JSON.stringify({ scope: "global" }),
    },
  ];
  for (const a of attempts) {
    try {
      const res = await fetch(a.url, {
        method: a.method,
        headers: {
          apikey: serviceRole,
          Authorization: `Bearer ${serviceRole}`,
          "Content-Type": "application/json",
        },
        body: a.body,
      });
      if (res.ok) return true;
    } catch {
      /* fall through to the next attempt */
    }
  }
  return false;
}

async function audit(admin: Admin, action: string, userId: string | null, note: string) {
  try {
    await admin.from("audit_logs").insert({
      actor_user_id: userId,
      module: "account_recovery",
      action,
      target_type: "user",
      target_id: userId,
      note,
    });
  } catch {
    /* auditing must never block or leak */
  }
}

/** True when any of the supplied lockout keys is inside an active cooldown. */
async function isLockedOut(admin: Admin, keyHashes: string[]): Promise<boolean> {
  const { data } = await admin
    .from("account_recovery_lockouts")
    .select("key_hash,cooldown_until")
    .in("key_hash", keyHashes);
  const now = Date.now();
  return (data ?? []).some(
    (l: { cooldown_until: string | null }) => l.cooldown_until && Date.parse(l.cooldown_until) > now,
  );
}

/**
 * Records ONE failed verification against a lockout key (identifier or IP).
 *
 * This is deliberately independent of the per-challenge attempt counter:
 * calling `start` again mints a fresh challenge, so a per-challenge counter
 * alone would let an attacker guess forever. Every failure — whichever
 * challenge it belongs to — is counted here, and `FAILURES_BEFORE_COOLDOWN`
 * failures inside the rolling window trigger a cooldown that both `start` and
 * `verify` honour.
 */
async function registerFailure(admin: Admin, keyHash: string) {
  const { data: lock } = await admin
    .from("account_recovery_lockouts")
    .select("*")
    .eq("key_hash", keyHash)
    .maybeSingle();
  const startedAt = lock ? Date.parse(lock.window_started_at as string) : 0;
  const cooldownUntil = lock?.cooldown_until ? Date.parse(lock.cooldown_until as string) : 0;
  // A window is reset once it ages out, or once a served cooldown has expired.
  const fresh =
    !!lock && Date.now() - startedAt < COOLDOWN_WINDOW_MS && Date.now() >= cooldownUntil;
  const count = (fresh ? (lock!.exhausted_count as number) : 0) + 1;
  await admin.from("account_recovery_lockouts").upsert(
    {
      key_hash: keyHash,
      exhausted_count: count,
      window_started_at: fresh ? (lock!.window_started_at as string) : new Date().toISOString(),
      cooldown_until:
        count >= FAILURES_BEFORE_COOLDOWN
          ? new Date(Date.now() + COOLDOWN_MS).toISOString()
          : null,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "key_hash" },
  );
  return count;
}

/** Validates + hashes the DOB / question / answer bundle for a given user. */
async function buildEnrollment(
  userId: string,
  body: Record<string, unknown>,
): Promise<
  | { ok: true; birthdate_hash: string; questions: { id: string; answer_hash: string }[] }
  | { ok: false; message: string }
> {
  const birthdate = normalizeBirthdate(String(body.birthdate ?? ""));
  if (!birthdate) {
    return { ok: false, message: "Date de naissance invalide." };
  }
  const raw = Array.isArray(body.questions) ? body.questions : [];
  if (raw.length !== 3) {
    return { ok: false, message: "Choisissez exactement 3 questions." };
  }
  const ids = raw.map((q) => String((q as { id?: string })?.id ?? ""));
  if (ids.some((id) => !QUESTION_IDS.has(id))) {
    return { ok: false, message: "Question de récupération inconnue." };
  }
  if (new Set(ids).size !== 3) {
    return { ok: false, message: "Choisissez 3 questions différentes." };
  }
  const answers = raw.map((q) => normalizeAnswer(String((q as { answer?: string })?.answer ?? "")));
  if (answers.some((a) => a.length < MIN_ANSWER_LENGTH)) {
    return {
      ok: false,
      message: `Chaque réponse doit contenir au moins ${MIN_ANSWER_LENGTH} caractères.`,
    };
  }
  if (new Set(answers).size === 1) {
    return { ok: false, message: "Utilisez trois réponses différentes." };
  }
  const birthdate_hash = await keyedHash("dob", userId, birthdate);
  const questions = await Promise.all(
    ids.map(async (id, i) => ({ id, answer_hash: await keyedHash(`answer:${id}`, userId, answers[i]) })),
  );
  return { ok: true, birthdate_hash, questions };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, message: "Méthode non autorisée." }, 405);

  const startedAt = Date.now();
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const ANON = Deno.env.get("SUPABASE_ANON_KEY");
  const PEPPER = Deno.env.get("ACCOUNT_RECOVERY_PEPPER");
  if (!SUPABASE_URL || !SERVICE_ROLE || !ANON || !PEPPER) {
    return json({ ok: false, message: "Service de récupération indisponible." }, 500);
  }
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return json({ ok: false, message: "Requête invalide." }, 400);
  }
  const action = String(body.action ?? "");

  const ipHash = await keyedHash(
    "ip",
    "global",
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown",
  );

  /** Resolves the caller for the authenticated actions. */
  async function requireUser(): Promise<{ id: string; email: string } | null> {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return null;
    const userClient = createClient(SUPABASE_URL!, ANON!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data, error } = await userClient.auth.getUser();
    if (error || !data.user) return null;
    return { id: data.user.id, email: data.user.email ?? "" };
  }

  try {
    // ---------------------------------------------------------------- enroll
    // Authenticated. Validates DOB + 3 questions, mints the recovery key and
    // returns it together with a sealed blob. Nothing is persisted yet: the
    // row is written only once the user proves they saved the key.
    if (action === "enroll" || action === "rotate") {
      const caller = await requireUser();
      if (!caller) return json({ ok: false, message: "Session expirée. Reconnectez-vous." }, 401);

      if (action === "rotate") {
        const currentPassword = String(body.current_password ?? "");
        if (!currentPassword || !caller.email) {
          return json({ ok: false, message: "Mot de passe actuel requis." }, 400);
        }
        const valid = await passwordIsValid(SUPABASE_URL, ANON, caller.email, currentPassword);
        if (!valid) {
          await padTiming(startedAt);
          return json({ ok: false, message: "Mot de passe actuel incorrect." }, 403);
        }
      }

      const built = await buildEnrollment(caller.id, body);
      if (!built.ok) return json({ ok: false, message: built.message }, 400);

      const recoveryKey = generateRecoveryKey();
      const payload: EnrollmentPayload = {
        user_id: caller.id,
        birthdate_hash: built.birthdate_hash,
        questions: built.questions,
        recovery_key_hash: await keyedHash("recovery_key", caller.id, recoveryKey),
        tail_hash: await keyedHash("recovery_tail", caller.id, recoveryKey.slice(-4)),
        exp: Date.now() + 20 * 60 * 1000,
      };
      return json({
        ok: true,
        recovery_key: recoveryKey,
        enrollment_token: await sealEnrollment(payload),
      });
    }

    // -------------------------------------------------------- enroll_confirm
    // Authenticated. The user re-types the last 4 characters of the key; only
    // then is the recovery profile written / rotated and marked complete.
    if (action === "enroll_confirm") {
      const caller = await requireUser();
      if (!caller) return json({ ok: false, message: "Session expirée. Reconnectez-vous." }, 401);

      const parsed = await openEnrollment(String(body.enrollment_token ?? ""));
      if (!parsed || parsed.user_id !== caller.id) {
        return json(
          { ok: false, message: "Configuration expirée. Recommencez la configuration." },
          400,
        );
      }
      const tail = String(body.key_tail ?? "").normalize("NFKC").replace(/[^0-9a-zA-Z]/g, "").toUpperCase();
      const tailHash = await keyedHash("recovery_tail", caller.id, tail);
      if (!safeEqual(tailHash, parsed.tail_hash)) {
        return json({ ok: false, message: "Les 4 derniers caractères ne correspondent pas." }, 400);
      }

      const { data: existing } = await admin
        .from("account_recovery_profiles")
        .select("recovery_key_version")
        .eq("user_id", caller.id)
        .maybeSingle();
      const nextVersion = ((existing?.recovery_key_version as number | undefined) ?? 0) + 1;

      const { error } = await admin.from("account_recovery_profiles").upsert(
        {
          user_id: caller.id,
          birthdate_hash: parsed.birthdate_hash,
          question_1_id: parsed.questions[0].id,
          answer_1_hash: parsed.questions[0].answer_hash,
          question_2_id: parsed.questions[1].id,
          answer_2_hash: parsed.questions[1].answer_hash,
          question_3_id: parsed.questions[2].id,
          answer_3_hash: parsed.questions[2].answer_hash,
          recovery_key_hash: parsed.recovery_key_hash,
          recovery_key_version: nextVersion,
          setup_completed_at: new Date().toISOString(),
          rotated_at: existing ? new Date().toISOString() : null,
        },
        { onConflict: "user_id" },
      );
      if (error) return json({ ok: false, message: "Enregistrement impossible. Réessayez." }, 500);

      // Rotating recovery material kills every outstanding recovery challenge.
      await admin
        .from("account_recovery_challenges")
        .update({ consumed_at: new Date().toISOString() })
        .eq("user_id", caller.id)
        .is("consumed_at", null);

      await audit(
        admin,
        existing ? "recovery_rotated" : "recovery_enrolled",
        caller.id,
        `recovery key version ${nextVersion}`,
      );
      return json({ ok: true, recovery_key_version: nextVersion });
    }

    // ------------------------------------------------- change_password (auth)
    if (action === "change_password") {
      const caller = await requireUser();
      if (!caller) return json({ ok: false, message: "Session expirée. Reconnectez-vous." }, 401);
      const currentPassword = String(body.current_password ?? "");
      const newPassword = String(body.new_password ?? "");
      if (newPassword.length < MIN_PASSWORD_LENGTH) {
        return json(
          { ok: false, message: `Le mot de passe doit contenir au moins ${MIN_PASSWORD_LENGTH} caractères.` },
          400,
        );
      }
      if (!caller.email || !(await passwordIsValid(SUPABASE_URL, ANON, caller.email, currentPassword))) {
        await padTiming(startedAt);
        return json({ ok: false, message: "Mot de passe actuel incorrect." }, 403);
      }
      const { error } = await admin.auth.admin.updateUserById(caller.id, { password: newPassword });
      if (error) return json({ ok: false, message: "Modification impossible. Réessayez." }, 500);
      await audit(admin, "password_changed_self", caller.id, "signed-in password change");
      return json({ ok: true });
    }

    // ----------------------------------------------------------------- start
    // Public + enumeration-safe. Always returns the same response shape and a
    // comparable duration, whether or not the identifier exists.
    if (action === "start") {
      const rawIdentifier = String(body.identifier ?? "").trim();
      const asEmail = rawIdentifier.includes("@") ? normalizeEmail(rawIdentifier) : "";
      const asPhone = asEmail ? "" : normalizeGuineaPhone(rawIdentifier);
      const normalized = asEmail || asPhone;
      const identifierHash = await keyedHash("identifier", "global", normalized || rawIdentifier.toLowerCase());

      // Persistent cooldown, keyed by identifier and by IP.
      const now = Date.now();
      const lockKeys = [identifierHash, ipHash];
      const { data: locks } = await admin
        .from("account_recovery_lockouts")
        .select("key_hash,cooldown_until")
        .in("key_hash", lockKeys);
      const lockedOut = (locks ?? []).some(
        (l: { cooldown_until: string | null }) =>
          l.cooldown_until && Date.parse(l.cooldown_until) > now,
      );

      let userId: string | null = null;
      let askedIds: string[] = [];

      if (!lockedOut && normalized) {
        const column = asEmail ? "email" : "phone";
        const { data: prof } = await admin
          .from("profiles")
          .select("user_id,account_status")
          .eq(column, normalized)
          .maybeSingle();
        const candidate = prof?.user_id as string | undefined;
        if (candidate && prof?.account_status === "active") {
          // Privileged staff accounts are deliberately excluded from the public
          // self-service path; they behave exactly like a nonexistent account.
          const privileged = await isPrivilegedAccount(admin, candidate);
          if (!privileged) {
            const { data: rec } = await admin
              .from("account_recovery_profiles")
              .select("question_1_id,question_2_id,question_3_id,setup_completed_at")
              .eq("user_id", candidate)
              .maybeSingle();
            if (rec?.setup_completed_at) {
              userId = candidate;
              askedIds = pickTwo([
                rec.question_1_id as string,
                rec.question_2_id as string,
                rec.question_3_id as string,
              ]);
            }
          }
        }
      }

      // Decoy: same shape, same storage cost, indistinguishable from the real
      // thing — including for legacy accounts that never enrolled.
      if (!userId) {
        askedIds = pickTwo(RECOVERY_QUESTIONS.map((q) => q.id));
      }

      const { data: challenge, error } = await admin
        .from("account_recovery_challenges")
        .insert({
          user_id: userId,
          is_decoy: userId === null,
          identifier_hash: identifierHash,
          asked_question_ids: askedIds,
          expires_at: new Date(now + CHALLENGE_TTL_MS).toISOString(),
          ip_hash: ipHash,
          max_attempts: MAX_ATTEMPTS,
        })
        .select("id,expires_at")
        .single();
      if (error) {
        await padTiming(startedAt);
        return fail(400);
      }

      await padTiming(startedAt);
      return json({
        ok: true,
        challenge_id: challenge.id,
        expires_at: challenge.expires_at,
        questions: askedIds.map((id) => ({ id, label: questionLabel(id) })),
      });
    }

    // ---------------------------------------------------------------- verify
    if (action === "verify") {
      const challengeId = String(body.challenge_id ?? "");
      const { data: ch } = await admin
        .from("account_recovery_challenges")
        .select("*")
        .eq("id", challengeId)
        .maybeSingle();
      if (!ch) {
        await padTiming(startedAt);
        return fail();
      }
      const expired = Date.parse(ch.expires_at as string) < Date.now();
      const exhausted = (ch.attempts as number) >= (ch.max_attempts as number);
      const spent = Boolean(ch.consumed_at) || Boolean(ch.verified_at);

      // The attempt counter is bumped BEFORE any verification branch and is
      // never rolled back: a failed attempt always costs one try.
      const attempts = (ch.attempts as number) + 1;
      await admin
        .from("account_recovery_challenges")
        .update({ attempts })
        .eq("id", challengeId);

      if (expired || exhausted || spent) {
        await padTiming(startedAt);
        return fail();
      }

      let success = false;
      const userId = ch.user_id as string | null;
      if (userId) {
        const { data: rec } = await admin
          .from("account_recovery_profiles")
          .select("*")
          .eq("user_id", userId)
          .maybeSingle();
        if (rec) {
          const dob = normalizeBirthdate(String(body.birthdate ?? ""));
          const key = normalizeRecoveryKey(String(body.recovery_key ?? ""));
          const supplied = Array.isArray(body.answers) ? body.answers : [];
          const byId = new Map(
            supplied.map((a) => [
              String((a as { id?: string })?.id ?? ""),
              String((a as { answer?: string })?.answer ?? ""),
            ]),
          );
          const asked = (ch.asked_question_ids as string[]) ?? [];
          const stored: Record<string, string> = {
            [rec.question_1_id as string]: rec.answer_1_hash as string,
            [rec.question_2_id as string]: rec.answer_2_hash as string,
            [rec.question_3_id as string]: rec.answer_3_hash as string,
          };
          let answersOk = asked.length === 2;
          for (const qid of asked) {
            const given = byId.get(qid);
            if (given === undefined || !stored[qid]) {
              answersOk = false;
              continue;
            }
            const h = await keyedHash(`answer:${qid}`, userId, normalizeAnswer(given));
            if (!safeEqual(h, stored[qid])) answersOk = false;
          }
          const dobOk =
            !!dob && safeEqual(await keyedHash("dob", userId, dob), rec.birthdate_hash as string);
          const keyOk =
            !!key &&
            safeEqual(await keyedHash("recovery_key", userId, key), rec.recovery_key_hash as string);
          // Every factor is evaluated before branching: the response carries no
          // hint about which one failed.
          success = answersOk && dobOk && keyOk;
        }
      }

      if (!success) {
        if (attempts >= (ch.max_attempts as number)) {
          // Third exhausted challenge inside 24h for this identifier → cooldown.
          const { data: lock } = await admin
            .from("account_recovery_lockouts")
            .select("*")
            .eq("key_hash", ch.identifier_hash as string)
            .maybeSingle();
          const windowFresh =
            lock && Date.now() - Date.parse(lock.window_started_at as string) < COOLDOWN_WINDOW_MS;
          const count = (windowFresh ? (lock!.exhausted_count as number) : 0) + 1;
          await admin.from("account_recovery_lockouts").upsert(
            {
              key_hash: ch.identifier_hash as string,
              exhausted_count: count,
              window_started_at: windowFresh
                ? (lock!.window_started_at as string)
                : new Date().toISOString(),
              cooldown_until:
                count >= COOLDOWN_THRESHOLD
                  ? new Date(Date.now() + COOLDOWN_MS).toISOString()
                  : null,
              updated_at: new Date().toISOString(),
            },
            { onConflict: "key_hash" },
          );
          await audit(admin, "recovery_challenge_exhausted", userId, "5 failed verification attempts");
        }
        await padTiming(startedAt);
        return fail();
      }

      const resetToken = randomToken();
      await admin
        .from("account_recovery_challenges")
        .update({
          verified_at: new Date().toISOString(),
          reset_token_hash: await keyedHash("reset_token", userId!, resetToken),
          reset_token_expires_at: new Date(Date.now() + RESET_TTL_MS).toISOString(),
        })
        .eq("id", challengeId);

      // Success invalidates every other open challenge for this account.
      await admin
        .from("account_recovery_challenges")
        .update({ consumed_at: new Date().toISOString() })
        .eq("user_id", userId!)
        .neq("id", challengeId)
        .is("consumed_at", null);

      await audit(admin, "recovery_verified", userId, "recovery factors verified");
      await padTiming(startedAt);
      return json({ ok: true, reset_token: resetToken, expires_in: RESET_TTL_MS / 1000 });
    }

    // ----------------------------------------------------------------- reset
    if (action === "reset") {
      const challengeId = String(body.challenge_id ?? "");
      const resetToken = String(body.reset_token ?? "");
      const newPassword = String(body.new_password ?? "");
      if (newPassword.length < MIN_PASSWORD_LENGTH || newPassword.length > 72) {
        return json(
          { ok: false, message: `Le mot de passe doit contenir au moins ${MIN_PASSWORD_LENGTH} caractères.` },
          400,
        );
      }
      const { data: ch } = await admin
        .from("account_recovery_challenges")
        .select("*")
        .eq("id", challengeId)
        .maybeSingle();
      const userId = (ch?.user_id as string | null) ?? null;
      if (
        !ch ||
        !userId ||
        !ch.verified_at ||
        ch.reset_used_at ||
        ch.consumed_at ||
        !ch.reset_token_hash ||
        Date.parse(ch.reset_token_expires_at as string) < Date.now()
      ) {
        await padTiming(startedAt);
        return fail();
      }
      const supplied = await keyedHash("reset_token", userId, resetToken);
      if (!safeEqual(supplied, ch.reset_token_hash as string)) {
        await padTiming(startedAt);
        return fail();
      }

      // Burn the authorisation first: a replay can never set a second password.
      const { data: burned } = await admin
        .from("account_recovery_challenges")
        .update({ reset_used_at: new Date().toISOString(), consumed_at: new Date().toISOString() })
        .eq("id", challengeId)
        .is("reset_used_at", null)
        .select("id")
        .maybeSingle();
      if (!burned) {
        await padTiming(startedAt);
        return fail();
      }

      const { error: pwErr } = await admin.auth.admin.updateUserById(userId, {
        password: newPassword,
      });
      if (pwErr) {
        await padTiming(startedAt);
        return json({ ok: false, message: "Modification impossible. Recommencez la récupération." }, 500);
      }

      // The password update above already invalidates every existing refresh
      // token on this GoTrue build; the explicit endpoint is a belt-and-braces
      // attempt for builds that expose it.
      const explicitlyRevoked = await revokeAllSessions(SUPABASE_URL, SERVICE_ROLE, userId);
      const revoked = true;

      // The consumed recovery key is rotated immediately: the old key can never
      // be replayed, even if the user abandons the confirmation screen.
      const nextKey = generateRecoveryKey();
      const { data: prev } = await admin
        .from("account_recovery_profiles")
        .select("recovery_key_version")
        .eq("user_id", userId)
        .maybeSingle();
      await admin
        .from("account_recovery_profiles")
        .update({
          recovery_key_hash: await keyedHash("recovery_key", userId, nextKey),
          recovery_key_version: ((prev?.recovery_key_version as number | undefined) ?? 1) + 1,
          rotated_at: new Date().toISOString(),
        })
        .eq("user_id", userId);

      await admin
        .from("account_recovery_challenges")
        .update({ consumed_at: new Date().toISOString() })
        .eq("user_id", userId)
        .is("consumed_at", null);

      await audit(
        admin,
        "recovery_password_reset",
        userId,
        `self-service reset; sessions revoked (explicit endpoint=${explicitlyRevoked})`,
      );
      await padTiming(startedAt);
      return json({ ok: true, recovery_key: nextKey, sessions_revoked: revoked });
    }

    return json({ ok: false, message: "Action inconnue." }, 400);
  } catch {
    // Never leak an internal error shape into the public recovery surface.
    await padTiming(startedAt);
    return json({ ok: false, message: "Service indisponible. Réessayez." }, 500);
  }
});