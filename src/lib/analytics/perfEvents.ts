import { supabase } from "@/integrations/supabase/client";

/**
 * Lightweight perf / lifecycle telemetry.
 * Writes to public.analytics_events when the table is available; otherwise
 * falls back to a console.debug so dev still gets feedback.
 */
export type PerfEventName =
  | "app_load_time"
  | "route_load_time"
  | "failed_network_request"
  | "offline_event"
  | "pwa_installed"
  | "low_data_mode_enabled";

type Payload = Record<string, unknown>;

const queue: Array<{ name: PerfEventName; payload: Payload; ts: string }> = [];
let flushing = false;

async function flush() {
  if (flushing || queue.length === 0) return;
  flushing = true;
  const batch = queue.splice(0, queue.length);
  try {
    const { data: { user } } = await supabase.auth.getUser();
    const rows = batch.map((e) => ({
      event_type: "performance",
      event_category: "performance",
      event_name: e.name,
      metadata: e.payload as never,
      user_id: user?.id ?? null,
      created_at: e.ts,
    }));
    const { error } = await supabase.from("analytics_events").insert(rows as never);
    if (error) console.debug("[perf] analytics insert failed", error.message);
  } catch (e) {
    console.debug("[perf] flush error", e);
  } finally {
    flushing = false;
  }
}

export function trackPerf(name: PerfEventName, payload: Payload = {}): void {
  queue.push({ name, payload, ts: new Date().toISOString() });
  // Coalesce — flush on idle
  if (typeof window !== "undefined") {
    const ric = (window as Window & { requestIdleCallback?: (cb: () => void) => void }).requestIdleCallback;
    if (ric) ric(flush);
    else setTimeout(flush, 250);
  }
}

/**
 * Boot-time hook: capture app_load_time once the document is interactive,
 * and listen for the lifecycle CustomEvents emitted elsewhere in the app.
 */
export function initPerfTelemetry(): void {
  if (typeof window === "undefined") return;
  const start = performance.now();
  const onReady = () => {
    trackPerf("app_load_time", {
      ms: Math.round(performance.now() - start),
      path: window.location.pathname,
      online: navigator.onLine,
    });
  };
  if (document.readyState === "complete") onReady();
  else window.addEventListener("load", onReady, { once: true });

  window.addEventListener("cc:offline_event", (e) => {
    const detail = (e as CustomEvent).detail ?? {};
    trackPerf("offline_event", detail);
  });
  window.addEventListener("cc:pwa_installed", () => trackPerf("pwa_installed", {}));
  window.addEventListener("cc:low_data_mode_enabled", (e) => {
    const detail = (e as CustomEvent).detail ?? {};
    trackPerf("low_data_mode_enabled", detail);
  });
}