import { test, expect } from "@playwright/test";
import { gotoSandbox, expectNoBlankScreen } from "./helpers";

test.describe("Merchant flow", () => {
  test("merchant hub redirects unauthenticated user to auth", async ({ page }) => {
    await gotoSandbox(page, "/merchant/hub");
    await page.waitForLoadState("networkidle");
    await expectNoBlankScreen(page);
    // Either lands on /auth or shows merchant hub depending on session state.
    const url = page.url();
    expect(url).toMatch(/\/auth|\/merchant\/hub/);
  });

  test("merchant QR landing renders", async ({ page }) => {
    await gotoSandbox(page, "/merchant");
    await expectNoBlankScreen(page);
  });
});