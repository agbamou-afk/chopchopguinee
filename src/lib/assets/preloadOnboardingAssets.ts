/**
 * Onboarding asset preloader.
 *
 * Warms the browser cache for the client (and optionally driver) onboarding
 * storybook images. Imports resolve to hashed URLs through Vite, so the same
 * URLs are reused by the actual `<img src>` tags inside the storybook.
 *
 * Design rules:
 *  - Never throw into the UI. Every promise resolves even if the image fails.
 *  - Idempotent: each URL is only fetched once per session.
 *  - Cooperative: starts only when the browser is idle / not actively rendering.
 *  - Does NOT mutate any onboarding / signup / auth state.
 */

import sceneWelcome from "@/assets/onboarding/scene-welcome.webp";
import sceneMoto from "@/assets/onboarding/scene-moto.webp";
import sceneMarche from "@/assets/onboarding/scene-marche.webp";
import sceneRepas from "@/assets/onboarding/scene-repas.webp";
import sceneWallet from "@/assets/onboarding/scene-wallet.webp";

import driverWelcome from "@/assets/onboarding/scene-driver-welcome.webp";
import driverMission from "@/assets/onboarding/scene-driver-mission.webp";
import driverNavigate from "@/assets/onboarding/scene-driver-navigate.webp";
import driverDeliver from "@/assets/onboarding/scene-driver-deliver.webp";
import driverEarnings from "@/assets/onboarding/scene-driver-earnings.webp";

export const CLIENT_ONBOARDING_IMAGES: readonly string[] = [
  sceneWelcome,
  sceneMoto,
  sceneRepas,
  sceneMarche,
  sceneWallet,
];

export const DRIVER_ONBOARDING_IMAGES: readonly string[] = [
  driverWelcome,
  driverMission,
  driverNavigate,
  driverDeliver,
  driverEarnings,
];

export const CLIENT_FIRST_SLIDE_IMAGE = sceneWelcome;
export const DRIVER_FIRST_SLIDE_IMAGE = driverWelcome;

const inflight = new Map<string, Promise<void>>();
const done = new Set<string>();

function preloadOne(src: string): Promise<void> {
  if (done.has(src)) return Promise.resolve();
  const existing = inflight.get(src);
  if (existing) return existing;
  const p = new Promise<void>((resolve) => {
    try {
      const img = new Image();
      img.decoding = "async";
      img.onload = () => { done.add(src); inflight.delete(src); resolve(); };
      img.onerror = () => { inflight.delete(src); resolve(); };
      img.src = src;
    } catch {
      resolve();
    }
  });
  inflight.set(src, p);
  return p;
}

function whenIdle(cb: () => void, timeout = 1500) {
  if (typeof window === "undefined") return;
  const w = window as unknown as {
    requestIdleCallback?: (cb: () => void, opts?: { timeout: number }) => number;
  };
  if (typeof w.requestIdleCallback === "function") {
    w.requestIdleCallback(cb, { timeout });
  } else {
    setTimeout(cb, 200);
  }
}

/** Preload first client slide eagerly, the rest in the background. */
export function preloadClientOnboardingAssets(opts?: { lowData?: boolean }): Promise<void> {
  if (typeof window === "undefined") return Promise.resolve();
  const first = preloadOne(CLIENT_FIRST_SLIDE_IMAGE);
  whenIdle(() => {
    const rest = CLIENT_ONBOARDING_IMAGES.filter((s) => s !== CLIENT_FIRST_SLIDE_IMAGE);
    if (opts?.lowData) {
      // Drip-load one at a time to avoid saturating slow links.
      rest.reduce<Promise<void>>(
        (chain, src) => chain.then(() => preloadOne(src)),
        Promise.resolve(),
      );
    } else {
      rest.forEach((src) => { void preloadOne(src); });
    }
  });
  return first;
}

/** Background driver onboarding warmup, used only when relevant. */
export function preloadDriverOnboardingAssets(): void {
  if (typeof window === "undefined") return;
  whenIdle(() => {
    DRIVER_ONBOARDING_IMAGES.forEach((src) => { void preloadOne(src); });
  }, 2500);
}

/** True once the client first-slide image has fully decoded. */
export function isClientFirstSlideReady(): boolean {
  return done.has(CLIENT_FIRST_SLIDE_IMAGE);
}

export function awaitClientFirstSlide(timeoutMs = 3500): Promise<void> {
  if (done.has(CLIENT_FIRST_SLIDE_IMAGE)) return Promise.resolve();
  return new Promise<void>((resolve) => {
    let settled = false;
    const finish = () => { if (!settled) { settled = true; resolve(); } };
    void preloadOne(CLIENT_FIRST_SLIDE_IMAGE).then(finish);
    setTimeout(finish, timeoutMs);
  });
}