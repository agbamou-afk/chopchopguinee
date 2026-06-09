/**
 * Register the PWA service worker, but never inside the Lovable preview iframe
 * or any preview/live-preview host — those would cache the iframe shell and
 * break the editor experience. Production / published domains only.
 */
export async function registerPwa(): Promise<void> {
  if (typeof window === "undefined") return;

  const inIframe = (() => {
    try { return window.self !== window.top; } catch { return true; }
  })();

  const host = window.location.hostname;
  const isPreviewHost =
    host.includes("id-preview--") ||
    host.includes("preview--") ||
    host.endsWith(".lovableproject.com") ||
    host.endsWith(".lovableproject-dev.com");

  // In editor preview / iframe: tear down any previously-registered SW so
  // contributors don't get stuck on a stale shell.
  if (inIframe || isPreviewHost) {
    if ("serviceWorker" in navigator) {
      try {
        const regs = await navigator.serviceWorker.getRegistrations();
        await Promise.all(regs.map((r) => r.unregister()));
      } catch { /* ignore */ }
    }
    return;
  }

  if (!("serviceWorker" in navigator)) return;

  try {
    const { registerSW } = await import("virtual:pwa-register");
    let refreshServiceWorker: ((reloadPage?: boolean) => Promise<void>) | undefined;
    refreshServiceWorker = registerSW({
      immediate: true,
      onNeedRefresh() {
        refreshServiceWorker?.(true).catch(() => {});
      },
      onOfflineReady() {},
      onRegisteredSW(_swUrl, registration) {
        // Hourly update check — tiny network ping, OK on mobile data.
        if (registration) {
          registration.update().catch(() => {});
          setInterval(() => registration.update().catch(() => {}), 60 * 60 * 1000);
        }
      },
    });

    // Track install for analytics
    window.addEventListener("appinstalled", () => {
      window.dispatchEvent(new CustomEvent("cc:pwa_installed"));
    });
  } catch (e) {
    console.warn("[pwa] registration skipped", e);
  }
}