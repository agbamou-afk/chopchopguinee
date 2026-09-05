import { describe, it, expect } from "vitest";
import { can, requiresApproval, PERMISSIONS, AdminModule } from "@/lib/admin/permissions";

/**
 * G6 — admin capability denial matrix (frontend mirror).
 * The database (`admin_capability`, `admin_four_eyes_gate`) stays authoritative;
 * these assertions protect the UI affordances from silent drift.
 */
describe("admin capability matrix", () => {
  it("A. god admin holds every module", () => {
    const modules = Object.keys(PERMISSIONS.god_admin) as AdminModule[];
    expect(modules.length).toBeGreaterThan(20);
    for (const m of modules) expect(can("god_admin", m, "delete")).toBe(true);
  });

  it("B. operations admin cannot touch wallet money", () => {
    expect(can("operations_admin", "wallet", "edit")).toBe(false);
    expect(can("operations_admin", "wallet", "approve")).toBe(false);
    expect(can("operations_admin", "payments", "view")).toBe(false);
  });

  it("C. operations admin keeps operational mutation", () => {
    for (const m of ["users", "drivers", "merchants", "orders", "support", "risk"] as AdminModule[]) {
      expect(can("operations_admin", m, "edit")).toBe(true);
    }
  });

  it("D. finance admin cannot mutate operations", () => {
    for (const m of ["drivers", "orders", "live_ops", "zones"] as AdminModule[]) {
      expect(can("finance_admin", m, "edit")).toBe(false);
    }
  });

  it("E. finance admin keeps money capabilities", () => {
    expect(can("finance_admin", "wallet", "approve")).toBe(true);
    expect(can("finance_admin", "payments", "edit")).toBe(true);
    expect(can("finance_admin", "reports", "export")).toBe(true);
  });

  it("F. staff administration is god-admin only", () => {
    expect(can("operations_admin", "admins", "view")).toBe(false);
    expect(can("finance_admin", "admins", "view")).toBe(false);
    expect(can("god_admin", "admins", "edit")).toBe(true);
  });

  it("G. feature flags and settings are god-admin only", () => {
    for (const r of ["operations_admin", "finance_admin"] as const) {
      expect(can(r, "flags", "edit")).toBe(false);
      expect(can(r, "settings", "edit")).toBe(false);
    }
  });

  it("H. no role at all is denied everywhere", () => {
    expect(can(null, "dashboard", "view")).toBe(false);
    expect(can(undefined, "wallet", "view")).toBe(false);
  });

  it("I. four-eyes actions are declared", () => {
    for (const a of ["wallet.correction", "pricing.change", "admin.create", "refund.large"]) {
      expect(requiresApproval(a)).toBe(true);
    }
    expect(requiresApproval("support.reply")).toBe(false);
  });

  it("J. non-god roles never hold delete except the explicit marche exception", () => {
    for (const role of ["operations_admin", "finance_admin"] as const) {
      for (const [mod, caps] of Object.entries(PERMISSIONS[role])) {
        if (caps?.includes("delete")) expect([role, mod]).toEqual(["operations_admin", "marche"]);
      }
    }
  });
});
