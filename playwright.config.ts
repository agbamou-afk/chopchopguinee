import { defineConfig, devices } from "@playwright/test";

/**
 * CHOP CHOP e2e configuration.
 *
 * Internal QA only — never run against production accounts/data.
 * Tests target the local Vite dev server (or PLAYWRIGHT_BASE_URL).
 */
const PORT = Number(process.env.PORT ?? 8080);
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? `http://localhost:${PORT}`;

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["list"]] : "list",
  use: {
    baseURL,
    trace: "on-first-retry",
    viewport: { width: 390, height: 844 },
    locale: "fr-FR",
  },
  projects: [
    { name: "mobile-chromium", use: { ...devices["Pixel 5"] } },
  ],
  webServer: process.env.PLAYWRIGHT_BASE_URL
    ? undefined
    : {
        command: "npm run dev",
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      },
});