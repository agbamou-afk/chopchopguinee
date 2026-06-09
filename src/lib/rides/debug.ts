type RideDebugPayload = Record<string, unknown>;

export function rideQaDebugEnabled() {
  if (import.meta.env.DEV) return true;
  if (typeof window === "undefined") return false;
  try {
    const params = new URLSearchParams(window.location.search);
    return params.get("rideQa") === "1" || localStorage.getItem("cc_ride_qa_debug") === "1";
  } catch {
    return false;
  }
}

export function rideQaDebug(event: string, payload: RideDebugPayload = {}) {
  if (!rideQaDebugEnabled()) return;
  // eslint-disable-next-line no-console
  console.debug(`[ride-qa] ${event}`, payload);
}