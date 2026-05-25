import { logNavigationEvent } from "./navigationTelemetry";
import type { LatLng } from "./geo";

/** Lightweight iOS detection (treats iPadOS-as-Mac heuristically). */
export function isIOS(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent || "";
  if (/iPhone|iPad|iPod/i.test(ua)) return true;
  // iPadOS 13+ reports as Mac; detect via touch points.
  return (
    /Macintosh/i.test(ua) &&
    typeof (navigator as any).maxTouchPoints === "number" &&
    (navigator as any).maxTouchPoints > 1
  );
}

export type ExternalTravelMode = "driving" | "two_wheeler" | "walking";

export interface ExternalNavInput {
  destination: LatLng;
  origin?: LatLng | null;
  mode?: ExternalTravelMode;
}

/**
 * Build a Google Maps directions URL. Used as a universal fallback because
 * Google Maps deep-links work on both iOS and Android browsers.
 */
export function buildGoogleMapsUrl({ origin, destination, mode = "driving" }: ExternalNavInput): string {
  const travel = mode === "two_wheeler" ? "two-wheeler" : mode === "walking" ? "walking" : "driving";
  const params = new URLSearchParams({ api: "1", destination: `${destination.lat},${destination.lng}`, travelmode: travel });
  if (origin) params.set("origin", `${origin.lat},${origin.lng}`);
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}

/** Apple Maps URL — preferred on iOS where the system map app is more familiar. */
export function buildAppleMapsUrl({ origin, destination, mode = "driving" }: ExternalNavInput): string {
  const dirflg = mode === "walking" ? "w" : "d";
  const params = new URLSearchParams({ daddr: `${destination.lat},${destination.lng}`, dirflg });
  if (origin) params.set("saddr", `${origin.lat},${origin.lng}`);
  return `https://maps.apple.com/?${params.toString()}`;
}

export interface OpenExternalNavOptions extends ExternalNavInput {
  /** Surface that triggered the open — used for telemetry. */
  surface: string;
  rideId?: string | null;
  missionId?: string | null;
  metadata?: Record<string, unknown>;
}

/**
 * Open the device-preferred external navigation app for `destination`.
 * - iOS → Apple Maps
 * - everything else → Google Maps
 * Logs `nav.external_open` to navigation_events + Analytics.
 */
export function openExternalNavigation(opts: OpenExternalNavOptions): void {
  const provider: "apple" | "google" = isIOS() ? "apple" : "google";
  const url = provider === "apple" ? buildAppleMapsUrl(opts) : buildGoogleMapsUrl(opts);
  void logNavigationEvent({
    event_name: "nav.external_open",
    surface: opts.surface,
    provider,
    ride_id: opts.rideId ?? null,
    mission_id: opts.missionId ?? null,
    metadata: { mode: opts.mode ?? "driving", has_origin: !!opts.origin, ...(opts.metadata ?? {}) },
  });
  try { window.open(url, "_blank", "noopener"); } catch { /* noop */ }
}