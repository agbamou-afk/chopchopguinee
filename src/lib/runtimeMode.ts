/**
 * Runtime mode helper.
 *
 * Production runtime modes are intentionally minimal:
 *
 *  - "public"  : visitor with no session. Public exploration only.
 *  - "live"    : signed-in non-admin human (live_client or live_driver
 *                depending on the in-app role/mode toggle).
 *  - "admin"   : signed-in admin user. Lands on /admin by default.
 *  - "sandbox" : internal/dev/QA. Debug panels + force-phase tools.
 *                Only enabled when explicitly requested (?sandbox=1,
 *                ?debug=1, localStorage flag, or DEV builds).
 *
 * The legacy "demo" runtime concept (demo client / demo driver showroom
 * accounts with auto-rotating fake missions and pickup bypass) has been
 * removed — public users get the same onboarding, and sandbox covers
 * internal testing.
 */
export type RuntimeMode = "public" | "live" | "admin" | "sandbox";

function urlMatches(re: RegExp): boolean {
  if (typeof window === "undefined") return false;
  return re.test(window.location.search);
}

function lsFlag(key: string): boolean {
  if (typeof window === "undefined") return false;
  try { return window.localStorage.getItem(key) === "1"; } catch { return false; }
}

/** Sandbox/test mode — internal dev tooling. Never auto-enabled in production. */
export function isSandboxMode(): boolean {
  if (urlMatches(/[?&]sandbox=1/)) return true;
  if (lsFlag("cc_sandbox")) return true;
  // DEV builds default to sandbox so engineers keep their tooling.
  if (import.meta.env.DEV) return true;
  return false;
}

/**
 * Resolve the active runtime mode. Sandbox always wins so an engineer
 * hitting `?sandbox=1` still gets the full debug surface regardless of
 * which account they are signed in as.
 */
export function getRuntimeMode(
  user?: { email?: string | null } | null,
  roles?: readonly string[] | null,
): RuntimeMode {
  if (isSandboxMode()) return "sandbox";
  if (!user) return "public";
  if (isAdminRole(roles)) return "admin";
  return "live";
}

export function isLiveMode(
  user?: { email?: string | null } | null,
  roles?: readonly string[] | null,
): boolean {
  return getRuntimeMode(user, roles) === "live";
}

/**
 * Lightweight role/user helpers used by Index/AppShell to decide what kind
 * of content is appropriate for the current session.
 *
 *  - PUBLIC : not signed in. Public exploration surfaces allowed.
 *  - LIVE   : signed-in non-admin human. Real data or empty states only.
 *  - ADMIN  : signed-in admin. Default landing is /admin.
 */
const ADMIN_ROLE_NAMES = new Set([
  "admin",
  "operations_admin",
  "finance_admin",
  "god_admin",
]);

export function isAdminRole(roles: readonly string[] | null | undefined): boolean {
  if (!roles) return false;
  return roles.some((r) => ADMIN_ROLE_NAMES.has(r));
}

export function isPublicMode(user: { email?: string | null } | null | undefined): boolean {
  return !user;
}

export function isLiveUser(
  user: { email?: string | null } | null | undefined,
  roles?: readonly string[] | null,
): boolean {
  if (!user) return false;
  if (isAdminRole(roles)) return false;
  return true;
}

export function isAdminUser(
  user: { email?: string | null } | null | undefined,
  roles?: readonly string[] | null,
): boolean {
  return !!user && isAdminRole(roles);
}