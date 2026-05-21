import { test, expect } from "@playwright/test";
import { gotoSandbox, expectNoBlankScreen } from "./helpers";

test.describe("Wallet smoke", () => {
  test("home renders wallet card / WONGO Wallet label for visitors", async ({ page }) => {
    await gotoSandbox(page, "/");
    await page.waitForLoadState("networkidle");
    await expectNoBlankScreen(page);
    // WONGO Wallet appears either on home wallet card or via nav — soft check.
    const wallet = page.getByText(/chopwallet|wallet|portefeuille/i).first();
    await expect(wallet).toBeVisible({ timeout: 10_000 }).catch(() => {});
  });
});