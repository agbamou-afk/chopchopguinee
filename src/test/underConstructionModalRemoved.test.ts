import { describe, it, expect } from "vitest";
import { readFileSync, existsSync, readdirSync, statSync } from "fs";
import { join } from "path";

/**
 * Post-lock cleanup proof: the "CHOPCHOP arrive bientôt / BÊTA" announcement
 * modal is fully removed from the active client render path. No component,
 * no hook, no invocation, no storage gate — so it cannot show to fresh users.
 */
function walk(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(p) && !p.includes("underConstructionModalRemoved")) out.push(p);
  }
  return out;
}

describe("Under construction modal removal", () => {
  const files = walk("src");

  it("no UnderConstructionModal component or hook files exist", () => {
    expect(existsSync("src/components/announcements/UnderConstructionModal.tsx")).toBe(false);
    expect(existsSync("src/hooks/useUnderConstructionAnnouncement.ts")).toBe(false);
  });

  it("no source file references the modal, hook, or its storage key", () => {
    const offenders = files.filter((f) => {
      const src = readFileSync(f, "utf8");
      return (
        src.includes("UnderConstructionModal") ||
        src.includes("useUnderConstructionAnnouncement") ||
        src.includes("cc_under_construction_seen")
      );
    });
    expect(offenders).toEqual([]);
  });

  it("no source file renders the announcement copy", () => {
    const offenders = files.filter((f) => {
      const src = readFileSync(f, "utf8");
      return src.includes("CHOPCHOP arrive bient");
    });
    expect(offenders).toEqual([]);
  });
});
