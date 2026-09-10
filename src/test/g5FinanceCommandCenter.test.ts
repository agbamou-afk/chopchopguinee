import { describe, it, expect, vi, beforeEach } from "vitest";
import fs from "node:fs";
import path from "node:path";

const rpc = vi.fn();
const from = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { rpc: (...a: unknown[]) => rpc(...a), from: (...a: unknown[]) => from(...a) },
}));

import {
  FINANCE_DENIED_MESSAGE, FINANCE_UNAVAILABLE_MESSAGE, OPS_ESCALATION,
  fetchFinanceOverview, formatGnf, modeLabel, relativeAge,
} from "@/lib/admin/financeCommandCenter";
import {
  FINANCE_FORBIDDEN_MODULES, FINANCE_READ_ONLY_MODULES, MODULE_CAPABILITY,
  PERMISSIONS, can, type AdminModule,
} from "@/lib/admin/permissions";

const root = process.cwd();
const read = (p: string) => fs.readFileSync(path.join(root, p), "utf8");
const app = read("src/App.tsx");
const sidebar = read("src/components/admin/AdminSidebar.tsx");
const home = read("src/components/admin/AdminHomeRoute.tsx");
const page = read("src/pages/admin/FinanceCommandCenter.tsx");
const model = read("src/lib/admin/financeCommandCenter.ts");
const reconciliation = read("src/pages/admin/WalletReconciliation.tsx");

beforeEach(() => { rpc.mockReset(); from.mockReset(); });

const overview = (over: Record<string, unknown> = {}) => ({
  generated_at: new Date().toISOString(),
  role: "finance_admin",
  snapshot: {
    topups_pending: 3, topups_review: 1, provider_events_open: 2, cashouts_pending: 4,
    settlements_pending: 1, payables_open: 6, payouts_open: 2, refunds_pending: 1,
    intents_review: 0, wallets_frozen: 0,
  },
  attention: [
    {
      kind: "cashout_pending", queue: "Retraits chauffeurs", label: "Retrait chauffeur en attente",
      reference: "abc12345", amount_gnf: 250000, state: "pending",
      since: new Date(Date.now() - 900_000).toISOString(), severity: "high",
      mode: "approval_required", href: "/admin/wallet/driver-cashouts",
    },
    {
      kind: "refund_pending", queue: "Remboursements", label: "Remboursement à décider",
      reference: "def67890", amount_gnf: 40000, state: "pending",
      since: new Date(Date.now() - 3_600_000).toISOString(), severity: "high",
      mode: "approval_required", href: "/admin/payments",
    },
  ],
  exceptions: [
    {
      code: "MASTER_WALLET_DEFICIT", severity: "high", amount_gnf: -100435, entity_count: 1,
      source_module: "treasury", account_code: "EQ_PLATFORM", detail: "DEF-FIN-001", state: "acknowledged",
    },
  ],
  exceptions_total: 1,
  exceptions_critical: 0,
  ...over,
});

// ------------------------------------------------------------- A. ROUTING
describe("G5 A — routing and finance surface reachability", () => {
  it("1. a Finance Admin lands on the Finance Command Center", () => {
    expect(home).toMatch(/finance_admin.*\/admin\/finance/s);
    expect(app).toMatch(/path="finance"[\s\S]{0,160}FinanceCommandCenter/);
  });

  it("2. every lawful finance module is reachable", () => {
    for (const m of ["wallet", "payments", "vendors", "reports", "analytics", "audit"] as AdminModule[]) {
      expect(can("finance_admin", m)).toBe(true);
    }
  });

  it("3. finance routes are capability-guarded, not merely hidden", () => {
    for (const p of ["finance", "wallet", "wallet/reconciliation", "wallet/driver-cashouts",
      "wallet/payouts", "treasury", "payments", "finance-policy", "vendors"]) {
      const re = new RegExp(`path="${p.replace("/", "\\/")}"[^>]*element=\\{<AdminRouteGuard`);
      expect(app, `route ${p} must be capability-guarded`).toMatch(re);
    }
  });

  it("4. sidebar finance entries derive from capability only", () => {
    expect(sidebar).toMatch(/group\.items\.filter\(\(i\) => can\(i\.module\)/);
    expect(sidebar).not.toMatch(/isAdmin|isSuperAdmin/);
    expect(sidebar).toContain('url: "/admin/finance"');
  });
});

// ------------------------------------------------------- B. READ MODEL TRUTH
describe("G5 B — command center truth", () => {
  it("5. counts come from the canonical read model", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchFinanceOverview();
    expect(rpc).toHaveBeenCalledWith("finance_command_overview");
    expect(res.ok && res.data.snapshot.cashouts_pending).toBe(4);
    expect(res.ok && res.data.attention).toHaveLength(2);
  });

  it("6. a failed read is never rendered as a fake zero", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "network" } });
    const res = await fetchFinanceOverview();
    expect(res.ok).toBe(false);
    expect(res.ok === false && res.error).toBe(FINANCE_UNAVAILABLE_MESSAGE);
    expect(page).toContain("Indisponible");
    expect(page).toMatch(/0 élément — lecture réussie/);
    expect(page).not.toMatch(/\?\?\s*0/);
  });

  it("7. a denial is reported as a denial, not as an outage", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "capability_denied: finance.wallet.read" } });
    const res = await fetchFinanceOverview();
    expect(res.ok === false && res.denied).toBe(true);
    expect(res.ok === false && res.error).toBe(FINANCE_DENIED_MESSAGE);
  });

  it("8. an unauthenticated read is a denial too", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "NOT_AUTHENTICATED" } });
    const res = await fetchFinanceOverview();
    expect(res.ok === false && res.denied).toBe(true);
  });

  it("9. a malformed payload never becomes a rendered number", async () => {
    rpc.mockResolvedValue({ data: "boom", error: null });
    const res = await fetchFinanceOverview();
    expect(res.ok).toBe(false);
  });

  it("10. every attention item deep-links to a canonical finance surface", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchFinanceOverview();
    const hrefs = res.ok ? res.data.attention.map((a) => a.href) : [];
    expect(hrefs.length).toBeGreaterThan(0);
    for (const h of hrefs) {
      expect(h.startsWith("/admin/")).toBe(true);
      expect(app).toContain(`path="${h.replace("/admin/", "")}"`);
    }
  });

  it("11. the read model calls exactly one read-only RPC and never writes", () => {
    const calls = [...model.matchAll(/rpc as any\)\("([a-z_]+)"/g)].map((m) => m[1]);
    expect(calls).toEqual(["finance_command_overview"]);
    expect(model).not.toMatch(/\.from\(|insert|update|delete|functions\.invoke/i);
    expect(page).not.toMatch(/\.from\(/);
  });
});

// --------------------------------------------------- C. EXECUTION HONESTY
describe("G5 C — execution honesty and four-eyes", () => {
  it("12. an approval-bound queue is labelled as such", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchFinanceOverview();
    const cashout = res.ok ? res.data.attention.find((a) => a.kind === "cashout_pending") : null;
    expect(cashout?.mode).toBe("approval_required");
    expect(modeLabel("approval_required")).toBe("Approbation requise");
  });

  it("13. a capability with no grant is never presented as executable", () => {
    expect(modeLabel(null)).toBe("Non autorisé");
    expect(modeLabel("read")).toBe("Lecture seule");
    expect(modeLabel("allow")).toBe("Exécution directe");
  });

  it("14. amounts are formatted, never invented", () => {
    expect(formatGnf(null)).toBe("—");
    expect(formatGnf(undefined)).toBe("—");
    expect(formatGnf(0)).toContain("0");
    expect(formatGnf(250000)).toMatch(/GNF$/);
  });

  it("15. unknown timestamps stay unknown", () => {
    expect(relativeAge(null)).toBe("—");
    expect(relativeAge("nope")).toBe("—");
    const now = Date.now();
    expect(relativeAge(new Date(now - 5 * 60_000).toISOString(), now)).toBe("5 min");
  });
});

// ------------------------------------------------- D. TREASURY EXCEPTIONS
describe("G5 D — treasury exceptions", () => {
  it("16. exceptions are named, quantified and never auto-compensated", async () => {
    rpc.mockResolvedValue({ data: overview(), error: null });
    const res = await fetchFinanceOverview();
    const exc = res.ok ? res.data.exceptions[0] : null;
    expect(exc?.code).toBe("MASTER_WALLET_DEFICIT");
    expect(exc?.amount_gnf).toBe(-100435);
    expect(page).toContain("jamais compensés automatiquement");
    expect(model).not.toMatch(/adjust|plug|balance_fix/i);
  });

  it("17. zero exceptions read as zero, unavailable reads as unavailable", async () => {
    rpc.mockResolvedValue({ data: overview({ exceptions: [], exceptions_total: 0 }), error: null });
    const res = await fetchFinanceOverview();
    expect(res.ok && res.data.exceptions_total).toBe(0);
    expect(page).toContain("0 exception — lecture réussie");
  });
});

// --------------------------------------------- E. OPERATIONS SEPARATION
describe("G5 E — operations and governance separation", () => {
  it("18. Finance never mutates operational modules", () => {
    for (const m of FINANCE_READ_ONLY_MODULES) {
      expect(can("finance_admin", m, "edit")).toBe(false);
    }
  });

  it("19. forbidden modules hold no permission row for Finance", () => {
    for (const m of FINANCE_FORBIDDEN_MODULES) {
      expect(PERMISSIONS.finance_admin[m]).toBeUndefined();
      expect(can("finance_admin", m)).toBe(false);
    }
  });

  it("20. staff, flags and settings stay governance-only", () => {
    expect(MODULE_CAPABILITY.admins).toBe("governance.staff.manage");
    expect(MODULE_CAPABILITY.flags).toBe("governance.flags.manage");
    expect(MODULE_CAPABILITY.settings).toBe("governance.settings.manage");
    for (const m of ["admins", "flags", "settings"] as AdminModule[]) {
      expect(can("finance_admin", m)).toBe(false);
      expect(can("operations_admin", m)).toBe(false);
    }
  });

  it("21. Operations still holds no finance module", () => {
    for (const m of ["wallet", "payments", "vendors"] as AdminModule[]) {
      expect(can("operations_admin", m)).toBe(false);
    }
  });

  it("22. the finance console escalates operational cases instead of acting", () => {
    expect(OPS_ESCALATION).toBe("Intervention Opérations requise");
    expect(page).toContain("OPS_ESCALATION");
  });

  it("23. a role-less session resolves to no finance access", () => {
    expect(can(null, "wallet")).toBe(false);
    expect(can(undefined, "payments")).toBe(false);
  });
});

// ----------------------------------------- F. NO DIRECT FINANCE TABLE WRITES
describe("G5 F — governed mutation only", () => {
  it("24. provider events are rejected through the governed RPC, never a table write", () => {
    expect(reconciliation).toContain("admin_reject_om_event");
    expect(reconciliation).not.toMatch(/from\("payment_provider_events"\)\s*\n?\s*\.update/);
  });

  it("25. the reconciliation console performs no direct write on canonical money tables", () => {
    const forbidden = /from\("(wallets|wallet_transactions|ledger_postings|ledger_journals|payout_orders|merchant_payables|payment_intents)"\)[\s\S]{0,40}\.(update|insert|delete)/;
    expect(reconciliation).not.toMatch(forbidden);
  });

  it("26. no arbitrary balance edit control exists on the finance command center", () => {
    expect(page).not.toMatch(/balance_gnf\s*=|setBalance|Corriger le solde/i);
  });
});
