import { describe, it, expect } from "vitest";
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  PERMISSIONS,
  OPERATIONS_FORBIDDEN_MODULES,
  FINANCE_FORBIDDEN_MODULES,
  MODULE_CAPABILITY,
  can,
  type AdminModule,
} from "@/lib/admin/permissions";

/**
 * G6 — final adversarial certification of the admin architecture, display layer.
 *
 * The database capability gate stays the authority. These checks defend the
 * seam the browser owns: no admin surface may write a governed table directly,
 * every mutation must travel through a governed RPC or edge endpoint, and the
 * frontend role map must not drift wider than the constitution.
 */

const SRC = join(process.cwd(), "src");

function walk(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(p) && !p.includes("/test/")) out.push(p);
  }
  return out;
}

const FILES = walk(SRC).map((p) => ({ p, s: readFileSync(p, "utf8") }));

/** Tables no browser code may insert/update/delete, whatever the caller's role. */
const GOVERNED_TABLES = [
  "payment_receiving_accounts",
  "admin_users",
  "user_roles",
  "admin_capability_grants",
  "approval_requests",
  "staff_lifecycle_requests",
  "audit_logs",
  "wallets",
  "wallet_transactions",
  "ledger_postings",
  "ledger_journals",
  "finance_policies",
  "driver_payout_policies",
  "merchant_settlement_policies",
  "payment_provider_events",
  "payment_intents",
  "app_settings",
  "feature_flags",
  "dormant_closed_account_liabilities",
];

describe("G6 · no direct write to a governed table", () => {
  for (const table of GOVERNED_TABLES) {
    it(`${table} is never mutated from the browser`, () => {
      const offenders = FILES.filter(({ s }) => {
        const re = new RegExp(
          `from\\(\\s*["'\`]${table}["'\`]\\s*\\)[\\s\\S]{0,400}?\\.(insert|update|upsert|delete)\\(`,
          "m",
        );
        return re.test(s);
      }).map(({ p }) => p.replace(process.cwd(), ""));
      expect(offenders).toEqual([]);
    });
  }
});

describe("G6 · receiving accounts travel through governed actions", () => {
  const lib = readFileSync(join(SRC, "lib/admin/receivingAccounts.ts"), "utf8");
  const ui = readFileSync(join(SRC, "components/admin/PaymentReceivingAccountsManager.tsx"), "utf8");

  it("exposes exactly the four governed server actions", () => {
    for (const fn of [
      "admin_receiving_account_create",
      "admin_receiving_account_update_metadata",
      "admin_receiving_account_set_active",
      "admin_receiving_account_replace_routing",
    ]) {
      expect(lib).toContain(fn);
    }
  });

  it("routing changes carry an approval identifier", () => {
    expect(lib).toContain("_g2_approval");
  });

  it("the manager never touches the table itself", () => {
    expect(ui).not.toMatch(/from\(\s*["'`]payment_receiving_accounts["'`]\s*\)[\s\S]{0,300}\.(insert|update|delete)\(/);
  });

  it("the manager only calls the governed client seam", () => {
    expect(ui).toContain("@/lib/admin/receivingAccounts");
  });

  it("denials are surfaced in French, never as a raw server string", () => {
    expect(lib).toContain("capability_denied");
    expect(lib).toContain("approbation");
  });

  it("routing history is shown as versioned and retirable", () => {
    expect(lib).toContain("retired_at");
    expect(lib).toContain("superseded_by");
    expect(lib).toContain("version");
  });
});

describe("G6 · approvals are decided server-side only", () => {
  const admins = readFileSync(join(SRC, "pages/admin/AdminsAdmin.tsx"), "utf8");

  it("the approval console calls the governed review action", () => {
    expect(admins).toContain("admin_review_approval");
  });

  it("the approval console never writes approval_requests directly", () => {
    expect(admins).not.toMatch(/from\(\s*["'`]approval_requests["'`]\s*\)[\s\S]{0,300}\.(insert|update|delete)\(/);
  });

  it("no admin surface fabricates a staff account", () => {
    expect(admins).not.toMatch(/from\(\s*["'`]admin_users["'`]\s*\)[\s\S]{0,300}\.insert\(/);
  });
});

describe("G6 · the retired staff endpoint stays retired", () => {
  const p = join(process.cwd(), "supabase/functions/admin-create-staff-user/index.ts");

  it("admin-create-staff-user is a tombstone", () => {
    if (!existsSync(p)) return;
    expect(readFileSync(p, "utf8")).toContain("ENDPOINT_RETIRED");
  });

  it("the governed lifecycle endpoint exists", () => {
    expect(existsSync(join(process.cwd(), "supabase/functions/admin-staff-lifecycle/index.ts"))).toBe(true);
  });
});

describe("G6 · frontend role map matches the constitution", () => {
  it("operations never reaches a financial or governance console", () => {
    for (const m of OPERATIONS_FORBIDDEN_MODULES) {
      expect(can("operations_admin", m, "view")).toBe(false);
      expect(can("operations_admin", m, "edit")).toBe(false);
    }
  });

  it("finance never reaches an operational or governance console", () => {
    for (const m of FINANCE_FORBIDDEN_MODULES) {
      expect(can("finance_admin", m, "edit")).toBe(false);
      expect(can("finance_admin", m, "approve")).toBe(false);
    }
  });

  it("no class other than god may delete outside its own domain", () => {
    const opsDeletes = (Object.keys(PERMISSIONS.operations_admin) as AdminModule[])
      .filter((m) => PERMISSIONS.operations_admin[m]?.includes("delete"));
    expect(opsDeletes.every((m) => m === "marche")).toBe(true);
  });

  it("every module is bound to a registry capability", () => {
    for (const m of Object.keys(PERMISSIONS.god_admin) as AdminModule[]) {
      expect(MODULE_CAPABILITY[m]).toBeTruthy();
    }
  });

  it("an unknown or absent role is denied everywhere", () => {
    for (const m of Object.keys(MODULE_CAPABILITY) as AdminModule[]) {
      expect(can(null, m, "view")).toBe(false);
    }
  });

  it("the legacy bare admin label confers nothing", () => {
    const hook = readFileSync(join(SRC, "hooks/useAdminAuth.ts"), "utf8");
    expect(hook).toContain("carries NO admin authority");
  });
});

describe("G6 · admin routes are guarded", () => {
  const app = readFileSync(join(SRC, "App.tsx"), "utf8");

  it("admin routes sit behind the admin guard", () => {
    expect(readFileSync(join(SRC, "components/admin/AdminLayout.tsx"), "utf8")).toContain("AdminGuard");
  });

  it("module-level guards exist for direct URL entry", () => {
    expect(app).toContain("AdminRouteGuard");
  });

  it("the guard refuses an account still on a temporary password", () => {
    const guard = readFileSync(join(SRC, "components/admin/AdminGuard.tsx"), "utf8");
    expect(guard).toContain("must_change_password");
    expect(guard).toContain("/admin/change-password");
  });
});

describe("G6 · no service credential reaches the browser", () => {
  it("no source file references a service role key", () => {
    const offenders = FILES.filter(({ s }) => s.includes("SUPABASE_SERVICE_ROLE_KEY")).map(({ p }) => p);
    expect(offenders).toEqual([]);
  });
});
