import { describe, it, expect, vi, beforeEach } from "vitest";
import fs from "node:fs";
import path from "node:path";

const rpc = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { rpc: (...a: unknown[]) => rpc(...a) },
}));

import {
  FINANCE_ESCALATION, OPS_DENIED_MESSAGE, OPS_UNAVAILABLE_MESSAGE,
  fetchOpsOverview, relativeAge,
} from "@/lib/admin/opsCommandCenter";
import {
  MODULE_CAPABILITY, OPERATIONS_FORBIDDEN_MODULES, PERMISSIONS, can,
  type AdminModule,
} from "@/lib/admin/permissions";

const root = process.cwd();
const app = fs.readFileSync(path.join(root, "src/App.tsx"), "utf8");
const sidebar = fs.readFileSync(path.join(root, "src/components/admin/AdminSidebar.tsx"), "utf8");
const home = fs.readFileSync(path.join(root, "src/components/admin/AdminHomeRoute.tsx"), "utf8");
const page = fs.readFileSync(path.join(root, "src/pages/admin/OpsCommandCenter.tsx"), "utf8");
const model = fs.readFileSync(path.join(root, "src/lib/admin/opsCommandCenter.ts"), "utf8");

beforeEach(() => rpc.mockReset());

const overview = (over: Record<string, unknown> = {}) => ({
  generated_at: new Date().toISOString(),
  role: "operations_admin",
  mode: "allow",
  snapshot: {
    rides_active: 2, rides_today: 9, rides_unassigned: 1, missions_active: 3,
    repas_active: 4, marche_active: 1, envoyer_active: 0, drivers_online: 5,
    drivers_approved: 12, driver_apps_pending: 2, merchant_apps_pending: 1,
    ops_cases_open: 3, support_open: 6, support_critical: 1, map_duplicates_open: 0,
  },
  attention: [
    {
      kind: "ride_unassigned", service: "Courses", label: "Course sans chauffeur",
      reference: "abc12345", state: "pending", since: new Date(Date.now() - 900_000).toISOString(),
      severity: "critical", finance_context: null, href: "/admin/live",
    },
    {
      kind: "repas_exception", service: "Repas", label: "Commande Repas en retard",
      reference: "def67890", state: "preparing", since: new Date(Date.now() - 3_600_000).toISOString(),
      severity: "high", finance_context: "Paiement: paid · Règlement: pending", href: "/admin/repas",
    },
  ],
  ...over,
});

// ---------------------------------------------------------------- A. ROUTING
describe("G4 A — routing and navigation", () => {
  it("1. an Operations Admin lands on the Operations Command Center", () => {
    expect(home).toMatch(/operations_admin.*\/admin\/ops/s);
    expect(app).toMatch(/path="ops"[\s\S]{0,120}OpsCommandCenter/);
  });

  it("2. lawful Operations modules are reachable", () => {
    const lawful: AdminModule[] = [
      "live_ops", "users", "drivers", "driver_groups", "merchants", "orders",
      "repas", "marche", "support", "risk", "notifications", "zones", "reports",
      "analytics", "audit",
    ];
    for (const m of lawful) expect(can("operations_admin", m)).toBe(true);
  });

  it("3. Finance-only modules are absent for Operations", () => {
    for (const m of ["wallet", "vendors", "payments"] as AdminModule[]) {
      expect(can("operations_admin", m)).toBe(false);
      expect(PERMISSIONS.operations_admin[m]).toBeUndefined();
    }
  });

  it("4. governance / staff modules are absent for Operations", () => {
    for (const m of ["admins", "settings", "flags", "promotions"] as AdminModule[]) {
      expect(can("operations_admin", m)).toBe(false);
    }
  });

  it("5. direct URL to a Finance mutation page is guarded", () => {
    for (const p of ["wallet", "wallet/reconciliation", "wallet/driver-cashouts",
      "wallet/payouts", "treasury", "payments", "finance-policy", "finance", "vendors",
      "repas/payments"]) {
      const re = new RegExp(`path="${p.replace("/", "\\/")}"[^>]*element=\\{<AdminRouteGuard`);
      expect(app, `route ${p} must be capability-guarded`).toMatch(re);
    }
  });

  it("6. direct URL to staff management is guarded by the admins module", () => {
    expect(app).toMatch(/path="admins" element=\{<AdminRouteGuard module="admins"/);
    expect(can("operations_admin", "admins")).toBe(false);
  });

  it("7. God keeps every route and Finance keeps its own", () => {
    for (const m of Object.keys(MODULE_CAPABILITY) as AdminModule[]) {
      expect(can("god_admin", m)).toBe(true);
    }
    expect(can("finance_admin", "payments")).toBe(true);
    expect(can("finance_admin", "wallet")).toBe(true);
  });

  it("every admin route in App.tsx carries a module guard", () => {
    const routes = [...app.matchAll(/<Route path="(?!\/)([^"]+)" element=\{([^]*?)\}\s*\/>/g)]
      .filter(([, p]) => !p.startsWith("/") && app.indexOf(`path="${p}"`) > app.indexOf('path="/admin"'));
    const unguarded = routes.filter(([, , el]) => !el.includes("AdminRouteGuard"));
    expect(unguarded.map(([, p]) => p)).toEqual([]);
  });
});

// ------------------------------------------------------------- B. DASHBOARD
describe("G4 B — dashboard truth", () => {
  it("8. counts derive from the canonical read model", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchOpsOverview();
    expect(rpc).toHaveBeenCalledWith("ops_command_overview");
    expect(res.ok && res.data.snapshot.rides_active).toBe(2);
    expect(res.ok && res.data.attention).toHaveLength(2);
  });

  it("9. a failed read is never rendered as a fake zero", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "network" } });
    const res = await fetchOpsOverview();
    expect(res.ok).toBe(false);
    expect(res.ok === false && res.error).toBe(OPS_UNAVAILABLE_MESSAGE);
    // the page distinguishes "0 item" from "unavailable"
    expect(page).toContain("Indisponible");
    expect(page).toMatch(/0 élément — lecture réussie/);
    expect(page).not.toMatch(/value=\{[^}]*\?\?\s*0\}/);
  });

  it("a denial is reported as a denial, not as an outage", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "capability_denied: ops.liveops.view" } });
    const res = await fetchOpsOverview();
    expect(res.ok === false && res.denied).toBe(true);
    expect(res.ok === false && res.error).toBe(OPS_DENIED_MESSAGE);
  });

  it("10. every queue item deep-links to a canonical operational destination", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchOpsOverview();
    const hrefs = res.ok ? res.data.attention.map((a) => a.href) : [];
    expect(hrefs.every((h) => h.startsWith("/admin/"))).toBe(true);
    for (const h of hrefs) expect(app).toContain(`path="${h.replace("/admin/", "")}"`);
  });

  it("11/12. the command center reuses canonical case surfaces, it does not fork them", () => {
    expect(page).toContain("/admin/marche/ops");
    expect(page).toContain("/admin/support");
    expect(model).not.toMatch(/insert|update|delete/i);
    expect(page).not.toMatch(/\.from\(/);
  });

  it("relative age is honest about unknown timestamps", () => {
    expect(relativeAge(null)).toBe("—");
    expect(relativeAge("not-a-date")).toBe("—");
    const now = Date.now();
    expect(relativeAge(new Date(now - 5 * 60_000).toISOString(), now)).toBe("5 min");
    expect(relativeAge(new Date(now - 3 * 3_600_000).toISOString(), now)).toBe("3 h");
  });
});

// --------------------------------------------- C/D. DRIVER, MERCHANT, SERVICES
describe("G4 C/D — operational authority and service coverage", () => {
  it("13/14. Operations may act on drivers and merchants", () => {
    expect(can("operations_admin", "drivers", "edit")).toBe(true);
    expect(can("operations_admin", "merchants", "edit")).toBe(true);
    expect(MODULE_CAPABILITY.drivers).toBe("ops.drivers.manage");
    expect(MODULE_CAPABILITY.merchants).toBe("ops.merchants.manage");
  });

  it("15. those same pages carry no Finance authority for Operations", () => {
    expect(can("operations_admin", "wallet", "edit")).toBe(false);
    expect(can("operations_admin", "payments", "edit")).toBe(false);
  });

  it("16-19. Moto/Bonbonna/Taxi, Envoyer, Repas and Marché all have Operations context", () => {
    expect(page).toMatch(/Courses \(Moto · Bonbonna · Taxi\)/);
    for (const s of ["Envoyer", "Repas", "Marché"]) expect(page).toContain(s);
    expect(can("operations_admin", "orders", "edit")).toBe(true);
    expect(can("operations_admin", "repas", "edit")).toBe(true);
    expect(can("operations_admin", "marche", "edit")).toBe(true);
  });
});

// -------------------------------------------------------- E. FINANCE SEPARATION
describe("G4 E — finance separation", () => {
  it("20. a finance-adjacent fact is readable as operational context", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchOpsOverview();
    const repas = res.ok ? res.data.attention.find((a) => a.kind === "repas_exception") : null;
    expect(repas?.finance_context).toMatch(/Paiement/);
    expect(page).toContain(FINANCE_ESCALATION);
  });

  it("21-26. no financial mutation control exists on any Operations surface", () => {
    const forbidden = /crédit(er)?\s+(le\s+)?wallet|débit(er)?|exécuter\s+le\s+versement|payout|cashout|réconciliation|treasury|trésorerie|politique financière|rail de paiement/i;
    expect(page).not.toMatch(forbidden);
    expect(model).not.toMatch(forbidden);
    // and the forbidden modules are not merely hidden: they hold no permission row
    for (const m of OPERATIONS_FORBIDDEN_MODULES) {
      expect(PERMISSIONS.operations_admin[m]).toBeUndefined();
    }
  });

  it("27. the read model calls exactly one read-only RPC and nothing else", () => {
    const calls = [...model.matchAll(/rpc as any\)\("([a-z_]+)"/g)].map((m) => m[1]);
    expect(calls).toEqual(["ops_command_overview"]);
    expect(model).not.toMatch(/functions\.invoke/);
  });
});

// ----------------------------------------------------- F/G. GOVERNANCE & AUTHORITY
describe("G4 F/G — governance separation and authority derivation", () => {
  it("28-31. staff, roles, flags and settings stay outside Operations", () => {
    for (const m of ["admins", "flags", "settings"] as AdminModule[]) {
      expect(PERMISSIONS.operations_admin[m]).toBeUndefined();
    }
    expect(MODULE_CAPABILITY.admins).toBe("governance.staff.manage");
    expect(MODULE_CAPABILITY.flags).toBe("governance.flags.manage");
    expect(MODULE_CAPABILITY.settings).toBe("governance.settings.manage");
  });

  it("32. sidebar entries are derived from capability, never from a generic isAdmin", () => {
    expect(sidebar).toMatch(/group\.items\.filter\(\(i\) => can\(i\.module\)\)/);
    expect(sidebar).not.toMatch(/isAdmin|isSuperAdmin/);
    expect(page).not.toMatch(/isAdmin/);
  });

  it("33. hidden UI is backed by a server capability gate, not by hiding alone", () => {
    expect(model).toContain("capability_denied");
    expect(page).toContain("useAdminAuth");
  });

  it("34/35. a customer or a role-less session resolves to no Operations access", () => {
    expect(can(null, "live_ops")).toBe(false);
    expect(can(undefined, "live_ops")).toBe(false);
    expect(can(null, "dashboard")).toBe(false);
  });

  it("every module maps to exactly one constitutional capability", () => {
    const modules = new Set(Object.keys(PERMISSIONS.god_admin));
    for (const m of modules) expect(MODULE_CAPABILITY[m as AdminModule]).toBeTruthy();
    expect(Object.keys(MODULE_CAPABILITY).length).toBe(modules.size);
  });
});
