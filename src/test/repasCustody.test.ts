import { describe, it, expect } from "vitest";
import {
  isRefusal,
  refusalMessage,
  translateCustodyError,
  type CustodyResult,
} from "@/lib/repas/custody";

describe("Repas R6 custody client contract", () => {
  it("treats a soft refusal as non-success and never as an error", () => {
    const r: CustodyResult = {
      ok: false,
      error: "CUSTODY_CODE_INVALID",
      attempts: 2,
      attempts_left: 3,
      locked: false,
    };
    expect(isRefusal(r)).toBe(true);
    expect(refusalMessage(r)).toContain("3 tentatives restantes");
  });

  it("surfaces the lockout instead of a retry count", () => {
    const r = { ok: false as const, error: "CUSTODY_CODE_LOCKED", attempts: 5, attempts_left: 0, locked: true };
    expect(refusalMessage(r)).toContain("bloqué");
  });

  it("singularises the last remaining attempt", () => {
    const r = { ok: false as const, error: "x", attempts: 4, attempts_left: 1, locked: false };
    expect(refusalMessage(r)).toContain("1 tentative restante");
  });

  it("does not treat a success envelope as a refusal", () => {
    expect(isRefusal({ ok: true })).toBe(false);
  });

  it("translates server photo-proof failures into actionable French", () => {
    expect(translateCustodyError("CUSTODY_PHOTO_REQUIRED")).toMatch(/photo/i);
    expect(translateCustodyError("CUSTODY_PHOTO_OWNER_MISMATCH")).toMatch(/coursier/i);
    expect(translateCustodyError("CUSTODY_PHOTO_PHASE_MISMATCH")).toMatch(/étape/i);
    expect(translateCustodyError("CUSTODY_DISPUTE_BLOCKED")).toMatch(/litige/i);
    expect(translateCustodyError("CUSTODY_NOT_ESTABLISHED")).toMatch(/restaurant/i);
  });

  it("passes unknown errors through untouched", () => {
    expect(translateCustodyError("boom")).toBe("boom");
  });
});
