import { test, expect } from "@playwright/test";
import { gotoSandbox, expectNoBlankScreen } from "./helpers";

const routes = [
  "/",
  "/auth",
  "/help",
  "/legal",
  "/notifications",
  "/settings/notifications",
  "/settings/privacy",
  "/offline",
];

test.describe("Route smoke", () => {
  for (const path of routes) {
    test(`renders ${path}`, async ({ page }) => {
      await gotoSandbox(page, path);
      await page.waitForLoadState("domcontentloaded");
      await expectNoBlankScreen(page);
      expect(await page.title()).not.toEqual("");
    });
  }
});