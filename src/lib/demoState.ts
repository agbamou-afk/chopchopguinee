import { ONBOARDING_DONE_KEY } from "@/components/onboarding/ClientOnboarding";
import { DRIVER_ONBOARDING_DONE_KEY } from "@/components/onboarding/DriverOnboarding";

export const DEMO_CLIENT_ONBOARDING_DONE_KEY = `${ONBOARDING_DONE_KEY}:demo`;
export const DEMO_DRIVER_ONBOARDING_DONE_KEY = `${DRIVER_ONBOARDING_DONE_KEY}:demo`;

export function demoScopedKey(baseKey: string, userId?: string | null, demo = false): string {
  return demo ? `${baseKey}:demo` : `${baseKey}:${userId ?? "guest"}`;
}

export function resetDemoState(userId?: string | null) {
  if (typeof window === "undefined") return;
  const localKeys = new Set<string>([
    DEMO_CLIENT_ONBOARDING_DONE_KEY,
    DEMO_DRIVER_ONBOARDING_DONE_KEY,
    `${ONBOARDING_DONE_KEY}:guest`,
    "cc_realtime_trip",
  ]);
  if (userId) {
    localKeys.add(`${ONBOARDING_DONE_KEY}:${userId}`);
    localKeys.add(`${DRIVER_ONBOARDING_DONE_KEY}:${userId}`);
  }
  localKeys.forEach((key) => {
    try { window.localStorage.removeItem(key); } catch { /* noop */ }
  });

  try {
    Object.keys(window.sessionStorage)
      .filter((key) => key === "cc_driver_mode" || key.startsWith("cc_demo") || key.includes(":ride-events:") || key.includes(":wallet-events:"))
      .forEach((key) => window.sessionStorage.removeItem(key));
  } catch { /* noop */ }
}
