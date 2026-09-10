import { describe, it, expect, vi, beforeEach } from "vitest";
import fs from "node:fs";
import path from "node:path";

const invoke = vi.fn();
const rpc = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { functions: { invoke: (...a: unknown[]) => invoke(...a) }, rpc: (...a: unknown[]) => rpc(...a) },
}));

import {
  APPROVAL_STATE_LABELS, LIFECYCLE_MESSAGES, QUORUM_UNAVAILABLE_MESSAGE, STAFF_CLASSES,
  StaffRosterRow, approvalState, availableActions, callStaffLifecycle, fetchStaffRoster,
  lifecycleMaterial, lifecycleMessage, lifecycleTargetType,
} from "@/lib/admin/staffLifecycle";

const root = process.cwd();
const edge = fs.readFileSync(path.join(root, "supabase/functions/admin-staff-lifecycle/index.ts"), "utf8");
const retired = fs.readFileSync(path.join(root, "supabase/functions/admin-create-staff-user/index.ts"), "utf8");
const ui = fs.readFileSync(path.join(root, "src/pages/admin/AdminsAdmin.tsx"), "utf8");
const guard = fs.readFileSync(path.join(root, "src/components/admin/AdminGuard.tsx"), "utf8");
const changePw = fs.readFileSync(path.join(root, "src/pages/admin/AdminChangePassword.tsx"), "utf8");

const row = (o: Partial<StaffRosterRow> = {}): StaffRosterRow => ({
  user_id: "u1", full_name: "Ops One", phone: null, canonical_role: "operations_admin",
  legacy_role: "ops_admin", status: "active", readiness: "ready", must_change_password: false,
  changed_password_at: null, created_at: new Date().toISOString(),
  last_action: null, last_action_at: null, last_outcome: null, ...o,
});

beforeEach(() => { invoke.mockReset(); rpc.mockReset(); });

describe("G3 — restricted staff classes", () => {
  it("offers only Operations and Finance, never God", () => {
    expect([...STAFF_CLASSES]).toEqual(["operations_admin", "finance_admin"]);
    expect(STAFF_CLASSES).not.toContain("god_admin" as never);
  });

  it("the creation UI exposes no God Admin option and no legacy promotion insert", () => {
    expect(ui).not.toMatch(/god_admin["']?\s*\}?\s*>/);
    expect(ui).not.toContain('from("admin_users")');
    expect(ui).not.toContain("admin-create-staff-user");
    expect(ui).toContain("STAFF_CLASSES");
  });

  it("never lets the browser choose or display a hard-coded temporary password", () => {
    expect(ui).not.toContain("Welcome%2026");
  });
});

describe("G3 — constitutionally impossible actions are hidden", () => {
  it("hides every action on the caller's own account", () => {
    expect(availableActions(row(), "u1")).toEqual([]);
  });
  it("hides every action on a God Admin target", () => {
    expect(availableActions(row({ canonical_role: "god_admin" }), "god")).toEqual([]);
    expect(availableActions(row({ legacy_role: "super_admin", canonical_role: null }), "god")).toEqual([]);
  });
  it("offers role change / reset / deactivate on active staff", () => {
    expect(availableActions(row(), "god")).toEqual(["ROLE_CHANGE", "ACCESS_RESET", "DEACTIVATE"]);
  });
  it("offers only reactivation on an inactive account", () => {
    expect(availableActions(row({ status: "suspended" }), "god")).toEqual(["REACTIVATE"]);
  });
});

describe("G3 — honest quorum and approval state", () => {
  it("uses the exact quorum-unavailable sentence", () => {
    expect(QUORUM_UNAVAILABLE_MESSAGE).toBe(
      "Quorum d’approbation indisponible — un deuxième God Admin actif est requis.",
    );
    expect(ui).toContain("QUORUM_UNAVAILABLE_MESSAGE");
  });
  it("never claims an approval executed the action", () => {
    expect(approvalState({ status: "approved", consumed_at: null, expires_at: null })).toBe("ready");
    expect(APPROVAL_STATE_LABELS.ready).toBe("Approuvée — exécutable");
    expect(ui).toContain("n’exécute rien");
  });
  it("reports consumed, expired and rejected truthfully", () => {
    expect(approvalState({ status: "approved", consumed_at: "2026-01-01", expires_at: null })).toBe("consumed");
    expect(approvalState({ status: "pending", consumed_at: null, expires_at: "2000-01-01" })).toBe("expired");
    expect(approvalState({ status: "rejected", consumed_at: null, expires_at: null })).toBe("rejected");
    expect(approvalState({ status: "pending", consumed_at: null, expires_at: null })).toBe("pending");
  });
  it("binds approval material to action + class + password policy", () => {
    expect(lifecycleMaterial({ action: "CREATE", role: "finance_admin" })).toEqual({
      action: "CREATE", admin_role: "finance_admin", must_change_password: true,
    });
    expect(lifecycleTargetType("CREATE")).toBe("staff_email");
    expect(lifecycleTargetType("ACCESS_RESET")).toBe("staff_user");
  });
});

describe("G3 — exact lifecycle error mapping", () => {
  it("maps every canonical outcome to a precise French message", () => {
    for (const code of [
      "CREATED", "ALREADY_COMPLETED", "ACCOUNT_ALREADY_EXISTS", "PENDING_APPROVAL",
      "APPROVER_QUORUM_UNAVAILABLE", "IDEMPOTENCY_INTENT_MISMATCH", "TARGET_CONFLICT",
      "FAILED_RETRYABLE", "FAILED_FINAL",
    ]) {
      expect(LIFECYCLE_MESSAGES[code]).toBeTruthy();
      expect(LIFECYCLE_MESSAGES[code]).not.toMatch(/non-2xx/i);
    }
  });

  it("never surfaces the generic Edge Function transport copy", async () => {
    invoke.mockResolvedValue({ data: null, error: { message: "Edge Function returned a non-2xx status code" } });
    const res = await callStaffLifecycle({ action: "CREATE" });
    expect(res.ok).toBe(false);
    expect(res.message).not.toMatch(/non-2xx/i);
    expect(res.result).toBe("FAILED_RETRYABLE");
  });

  it("passes a structured server outcome straight through", async () => {
    invoke.mockResolvedValue({ data: { ok: false, result: "ACCOUNT_ALREADY_EXISTS", message: "x" }, error: null });
    const res = await callStaffLifecycle({ action: "CREATE" });
    expect(res.result).toBe("ACCOUNT_ALREADY_EXISTS");
    expect(lifecycleMessage(res.result, null)).toContain("existe déjà");
  });
});

describe("G3 — roster readiness surface", () => {
  it("reads the roster through the governed RPC and reports denial", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "G3_READINESS_DENIED" } });
    const res = await fetchStaffRoster();
    expect(rpc).toHaveBeenCalledWith("admin_staff_roster");
    expect(res.rows).toEqual([]);
    expect(res.error).toContain("READINESS_DENIED");
  });
  it("renders readiness, status and last lifecycle outcome", () => {
    expect(ui).toContain("READINESS_LABELS");
    expect(ui).toContain("last_outcome");
  });
});

describe("G3 — password gate", () => {
  it("blocks every admin route until the temporary password is changed", () => {
    expect(guard).toContain("must_change_password");
    expect(guard).toContain('Navigate to="/admin/change-password"');
  });
  it("clears the flag only after Auth accepted the new password", () => {
    const upd = changePw.indexOf("auth.updateUser");
    const clear = changePw.indexOf("admin_clear_must_change_password");
    expect(upd).toBeGreaterThan(-1);
    expect(clear).toBeGreaterThan(upd);
  });
  it("uses the shared PasswordInput show/hide primitive", () => {
    expect(changePw).toContain("PasswordInput");
    expect(changePw).not.toMatch(/<Input[^>]*type="password"/);
  });
});

describe("G3 — edge lifecycle contract", () => {
  it("always answers HTTP 200 with a machine-readable outcome", () => {
    expect(edge).toContain("status: 200");
    expect(/status:\s*(4\d\d|5\d\d)/.test(edge)).toBe(false);
  });
  it("refuses a duplicate email instead of creating a second Auth user", () => {
    expect(edge).toContain("ACCOUNT_ALREADY_EXISTS");
    expect(edge).toContain("findAuthUserByEmail");
  });
  it("reuses the Auth identity of a timed-out attempt via the lifecycle request id", () => {
    expect(edge).toContain("staff_lifecycle_request_id");
    expect(edge).toContain("admin_staff_record_auth_as");
  });
  it("records the Auth identity before finalizing any authority", () => {
    expect(edge.indexOf("admin_staff_record_auth_as")).toBeLessThan(
      edge.indexOf("admin_staff_finalize_create_as"),
    );
  });
  it("never persists or logs a temporary password", () => {
    expect(edge).not.toMatch(/insert\([^)]*password/is);
    expect(edge).not.toMatch(/console\.(log|error|warn)\([^)]*(tempPassword|password)/i);
    expect(edge).toContain("makeTempPassword");
  });
  it("resets access through the Auth admin API and forces a password change", () => {
    expect(edge).toContain("auth.admin.updateUserById");
    expect(edge).toContain("revokeSessions");
  });
  it("keeps four-eyes, quorum and idempotency in the database", () => {
    expect(edge).toContain("admin_staff_lifecycle_begin_as");
    expect(edge).toContain("_approval_id");
    expect(edge).toContain("_idempotency_key");
  });
  it("retires the ungoverned creation endpoint with zero writes", () => {
    expect(retired).toContain("ENDPOINT_RETIRED");
    expect(retired).not.toContain("SERVICE_ROLE_KEY");
    expect(retired).not.toContain("createUser");
  });
});
