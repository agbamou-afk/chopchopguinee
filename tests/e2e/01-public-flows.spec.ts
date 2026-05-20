import { test, expect } from "@playwright/test";
import { gotoSandbox, expectNoBlankScreen, expectBottomNav } from "./helpers";

test.describe("Public flows", () => {
  test("app loads home without blank screen", async ({ page }) => {
    await gotoSandbox(page, "/");
    await page.waitForLoadState("networkidle");
    await expectNoBlankScreen(page);
  });

  test("bottom nav is visible on home", async ({ page }) => {
    await gotoSandbox(page, "/");
    await expectBottomNav(page);
  });

  test("404 route renders NotFound page", async ({ page }) => {
    await gotoSandbox(page, "/__definitely_not_a_route__");
    await expect(page.locator("body")).toContainText(/404|introuvable|not found/i);
  });

  test("auth page renders", async ({ page }) => {
    await gotoSandbox(page, "/auth");
    await expectNoBlankScreen(page);
  });
});