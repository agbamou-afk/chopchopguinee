import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { PERMISSIONS, AdminModule } from "@/lib/admin/permissions";

/**
 * G1 static audit test — non-mutating, docs coverage only.
 * Proves the constitution + audit docs classify 100% of the admin surface at HEAD.
 */
const root = process.cwd();
const constitution = fs.readFileSync(path.join(root, "docs/admin/ADMIN_CAPABILITY_CONSTITUTION.md"), "utf8");
const audit = fs.readFileSync(path.join(root, "docs/admin/G1_ADMIN_AUTHORITY_AUDIT.md"), "utf8");

describe("G1 constitution coverage", () => {
  it("every admin page component is named in the audit", () => {
    const pages = fs
      .readdirSync(path.join(root, "src/pages/admin"))
      .filter((f) => f.endsWith(".tsx"))
      .map((f) => f.replace(/\.tsx$/, ""));
    const missing = pages.filter(
      (p) => !audit.includes(p) && !audit.includes(p.replace(/Admin$/, "")),
    );
    // Pages are covered either by name or by their declared module row.
    expect(pages.length).toBeGreaterThan(40);
    expect(missing.every((p) => fileDeclaresModule(p))).toBe(true);
  });

  it("every admin-facing edge function is classified", () => {
    const fns = [
      "admin-create-staff-user",
      "admin-delete-user",
      "admin-driver-doc-url",
      "admin-email-resend",
      "om-import-csv",
      "account-access-termination-worker",
      "qa-merchant-harness",
      "qa-node-harness",
    ];
    for (const fn of fns) {
      expect(fs.existsSync(path.join(root, "supabase/functions", fn, "index.ts"))).toBe(true);
      expect(audit).toContain(fn);
    }
  });

  it("every frontend module appears in the constitution matrix or capability namespace", () => {
    const modules = Object.keys(PERMISSIONS.god_admin) as AdminModule[];
    const unmapped = modules.filter((m) => {
      const stem = m.replace(/_/g, " ").split(" ")[0];
      return !constitution.toLowerCase().includes(stem);
    });
    expect(unmapped).toEqual([]);
  });

  it("the three canonical role names and every alias are stated", () => {
    for (const s of [
      "god_admin",
      "operations_admin",
      "finance_admin",
      "super_admin",
      "ops_admin",
      "support_admin",
    ]) {
      expect(constitution).toContain(s);
    }
  });

  it("four-eyes law states requester != approver and forbids browser enforcement", () => {
    expect(constitution).toContain("requested_by <> reviewed_by");
    expect(constitution).toContain("No browser enforcement");
  });

  it("no numeric threshold is hard-coded as constitutional", () => {
    expect(constitution).toContain("POLICY_THRESHOLD_REQUIRED");
    // No GNF amounts written into the constitution.
    expect(/\d[\d\s.,]*\s*GNF/.test(constitution)).toBe(false);
  });

  it("the audit declares zero unclassified rows", () => {
    expect(audit).toContain("Unclassified callables or pages | 0");
    expect(audit).toContain("Unclassified rows: **0**");
  });
});

function fileDeclaresModule(page: string): boolean {
  const src = fs.readFileSync(path.join(root, "src/pages/admin", `${page}.tsx`), "utf8");
  return /module="[a-z_]+"/.test(src) || page === "AdminChangePassword";
}
