import { expect, Page } from "@playwright/test";

/**
 * Dismiss the splash screen by waiting it out (it auto-hides ~4.4s)
 * or by setting the session flag before navigation when faster.
 */
export async function skipSplash(page: Page) {
  await page.addInitScript(() => {
    try {
      sessionStorage.setItem("cc_splash_shown", "1");
      // Mark onboarding done by default — individual tests can clear it.
      // localStorage.setItem("cc_client_onboarding_done", "1");
    } catch {}
  });
}

export async function gotoSandbox(page: Page, path = "/") {
  await skipSplash(page);
  const sep = path.includes("?") ? "&" : "?";
  await page.goto(`${path}${sep}sandbox=1`);
}

export async function expectNoBlankScreen(page: Page) {
  // Cheap heuristic — body should have visible non-empty content.
  const text = (await page.locator("body").innerText()).trim();
  expect(text.length, "page body should not be blank").toBeGreaterThan(0);
}

export async function expectBottomNav(page: Page) {
  // Bottom nav on Index uses NavLink items rendered as buttons/links.
  const nav = page.locator("nav, [role='navigation']").first();
  await expect(nav).toBeVisible({ timeout: 10_000 });
}