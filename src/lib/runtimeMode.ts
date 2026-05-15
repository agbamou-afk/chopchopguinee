/**
 * Runtime mode helper.
 *
 * The CHOP CHOP super-app runs in three distinct runtime modes. The mode
 * controls how strict the pickup handshake is, whether demo bypass affordances
 * are visible, and whether internal debug tooling is mounted.
 *
 *  - "live"    : real production users. Full pickup security, no bypass.
 *  - "demo"    : presentation flow (linked client+driver demo accounts).
 *                Smooth one-tap pickup confirm, no scanner required.
 *  - "sandbox" : internal/admin/dev. All debug panels + force-phase tools.
 */
export type RuntimeMode = "live" | "demo" | "sandbox";

const DEMO_EMAILS = new Set(["demo.client@chopchop.gn", "demo.driver@chopchop.gn"]);

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

/** Demo mode — used for the linked two-account presentation flow. */
export function isDemoMode(email?: string | null): boolean {
  if (email && DEMO_EMAILS.has(email.toLowerCase())) return true;
  if (urlMatches(/[?&]demo=(1|linked|driver)/)) return true;
  return false;
}

/** Driver demo flavour — used to force the chauffeur first-run path. */
export function isDemoDriverMode(email?: string | null): boolean {
  if (email?.toLowerCase() === "demo.driver@chopchop.gn") return true;
  if (urlMatches(/[?&]demo=driver\b/)) return true;
  return false;
}

/**
 * Resolve the active runtime mode. Sandbox wins over demo wins over live so
 * that a developer hitting `?sandbox=1` while logged in as a demo account
 * still gets the full debug surface.
 */
export function getRuntimeMode(email?: string | null): RuntimeMode {
  if (isSandboxMode()) return "sandbox";
  if (isDemoMode(email)) return "demo";
  return "live";
}

export function isLiveMode(email?: string | null): boolean {
  return getRuntimeMode(email) === "live";
}

/** True for any non-live mode (demo or sandbox) — handy for soft gating. */
export function isNonLiveMode(email?: string | null): boolean {
  return getRuntimeMode(email) !== "live";
}

/**
 * Lightweight role/user helpers used by Index/AppShell to decide what kind
 * of content is appropriate for the current session.
 *
 *  - PUBLIC : not signed in. Showroom placeholders allowed.
 *  - DEMO   : demo client/driver account or `?demo=` flag. Demo placeholders allowed.
 *  - LIVE   : signed-in non-demo human. Real data or empty states only.
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

export function isDemoUser(user: { email?: string | null } | null | undefined): boolean {
  return isDemoMode(user?.email ?? null);
}

export function isLiveUser(
  user: { email?: string | null } | null | undefined,
  roles?: readonly string[] | null,
): boolean {
  if (!user) return false;
  if (isDemoUser(user)) return false;
  if (isAdminRole(roles)) return false;
  return true;
}

export function isAdminUser(
  user: { email?: string | null } | null | undefined,
  roles?: readonly string[] | null,
): boolean {
  return !!user && isAdminRole(roles);
}