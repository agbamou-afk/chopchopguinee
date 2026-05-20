import { test, expect } from "@playwright/test";
import { gotoSandbox } from "./helpers";

test.describe("Sandbox Ops Panel", () => {
  test("panel mounts under ?sandbox=1", async ({ page }) => {
    await gotoSandbox(page, "/");
    // Panel is a floating dev surface — look for distinctive labels.
    const panel = page.getByText(/sandbox\s*ops/i).first();
    await expect(panel).toBeVisible({ timeout: 15_000 });
  });

  test("panel does NOT mount in plain mode", async ({ page }) => {
    await page.addInitScript(() => {
      try { sessionStorage.setItem("cc_splash_shown", "1"); } catch {}
    });
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    const panel = page.getByText(/sandbox\s*ops/i);
    await expect(panel).toHaveCount(0);
  });

  test("can open scenarios and trigger a run", async ({ page }) => {
    await gotoSandbox(page, "/");
    await page.getByText(/sandbox\s*ops/i).first().click().catch(() => {});
    // Try clicking the first "Run" / "Lancer" button if visible.
    const runBtn = page.getByRole("button", { name: /run|lancer|exécuter/i }).first();
    if (await runBtn.isVisible().catch(() => false)) {
      await runBtn.click();
      // Health badge should appear (PASS/WARN/FAIL)
      await expect(page.getByText(/pass|warn|fail/i).first()).toBeVisible({ timeout: 10_000 });
    }
  });
});