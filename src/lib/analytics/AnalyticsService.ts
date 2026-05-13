/**
 * AnalyticsService — single client-side entry point for tracked events.
 *
 * - Privacy first: respects PrivacyConsentManager. Risk + auth + payment
 *   failure events are always logged (set in ALWAYS_ON_EVENTS).
 * - Batched: events are buffered in-memory and flushed every 4s, on visibility
 *   change, and on page unload. Network failures are dropped silently — never
 *   block UX.
 * - Anonymous-friendly: an opaque session id is generated and reused.
 */
import { supabase } from "@/integrations/supabase/client";
import {
  ALWAYS_ON_EVENTS,
  categoryFor,
  type EventName,
} from "./eventTaxonomy";
import { Consent } from "./consent";

const APP_VERSION = "1.0.0";
const FLUSH_INTERVAL_MS = 4000;
const MAX_BUFFER = 25;
const SESSION_KEY = "cc.session.v1";

export interface TrackOptions {
  /** Free-form metadata. Avoid PII; never include raw text the user typed. */
  metadata?: Record<string, unknown>;
  /** Override the route (defaults to current pathname). */
  route?: string;
  /** Optional zone (consented). */
  zone?: { country?: string; city?: string; commune?: string; neighborhood?: string };
  /** Service area shorthand (moto, food, market, wallet, …). */
  serviceArea?: string;
}

interface QueuedEvent {
  user_id: string | null;
  anonymous_session_id: string | null;
  event_type: string;
  event_category: string;
  event_name: string;
  route: string | null;
  service_area: string | null;
  device_type: string | null;
  app_version: string | null;
  os: string | null;
  language: string | null;
  zone_country: string | null;
  zone_city: string | null;
  zone_commune: string | null;
  zone_neighborhood: string | null;
  metadata: Record<string, unknown>;
}

function getSessionId(): string {
  if (typeof window === "undefined") return "ssr";
  try {
    let id = window.localStorage.getItem(SESSION_KEY);
    if (!id) {
      id = "anon_" + Math.random().toString(36).slice(2) + Date.now().toString(36);
      window.localStorage.setItem(SESSION_KEY, id);
    }
    return id;
  } catch {
    return "anon_session";
  }
}

function detectDevice(): { device: string; os: string; lang: string } {
  if (typeof navigator === "undefined") return { device: "unknown", os: "unknown", lang: "fr" };
  const ua = navigator.userAgent || "";
  let device = "desktop";
  if (/Mobi|Android|iPhone/i.test(ua)) device = "mobile";
  else if (/iPad|Tablet/i.test(ua)) device = "tablet";
  let os = "other";
  if (/Android/i.test(ua)) os = "android";
  else if (/iPhone|iPad|iOS/i.test(ua)) os = "ios";
  else if (/Windows/i.test(ua)) os = "windows";
  else if (/Mac OS X/i.test(ua)) os = "macos";
  else if (/Linux/i.test(ua)) os = "linux";
  return { device, os, lang: navigator.language || "fr" };
}

let buffer: QueuedEvent[] = [];
let currentUserId: string | null = null;
let flushTimer: number | null = null;
let initialized = false;

async function flush() {
  if (buffer.length === 0) return;
  const batch = buffer.splice(0, buffer.length);
  // Insert in background — never await user-blocking calls; never throw.
  try {
    await supabase.from("analytics_events").insert(batch);
  } catch {
    /* swallow — analytics must never break the app */
  }
}

function scheduleFlush() {
  if (flushTimer != null || typeof window === "undefined") return;
  flushTimer = window.setTimeout(() => {
    flushTimer = null;
    void flush();
  }, FLUSH_INTERVAL_MS);
}

function shouldRecord(name: string): boolean {
  if (ALWAYS_ON_EVENTS.has(name)) return true;
  return Consent.current().basic_analytics;
}

function shouldRecordZone(): boolean {
  return Consent.current().location_improvements;
}

export const Analytics = {
  /** Wire up flush triggers and session bootstrap. Idempotent. */
  init() {
    if (initialized || typeof window === "undefined") return;
    initialized = true;

    // Track auth user id reactively
    supabase.auth.getSession().then(({ data }) => {
      currentUserId = data.session?.user.id ?? null;
      if (currentUserId) void Consent.loadForUser(currentUserId);
    });
    supabase.auth.onAuthStateChange((_e, session) => {
      currentUserId = session?.user.id ?? null;
      if (currentUserId) void Consent.loadForUser(currentUserId);
    });

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") void flush();
    });
    window.addEventListener("pagehide", () => void flush());
    window.addEventListener("beforeunload", () => void flush());
  },

  /** Fire an event. Non-blocking, never throws. */
  track(name: EventName | string, opts: TrackOptions = {}) {
    try {
      if (!shouldRecord(name)) return;
      const { device, os, lang } = detectDevice();
      const route =
        opts.route ?? (typeof window !== "undefined" ? window.location.pathname : null);
      const z = shouldRecordZone() ? opts.zone ?? {} : {};
      buffer.push({
        user_id: currentUserId,
        anonymous_session_id: currentUserId ? null : getSessionId(),
        event_type: name.includes(".") ? name.split(".")[1] : "action",
        event_category: categoryFor(name as EventName),
        event_name: name,
        route: route ?? null,
        service_area: opts.serviceArea ?? null,
        device_type: device,
        app_version: APP_VERSION,
        os,
        language: lang,
        zone_country: z.country ?? null,
        zone_city: z.city ?? null,
        zone_commune: z.commune ?? null,
        zone_neighborhood: z.neighborhood ?? null,
        metadata: opts.metadata ?? {},
      });
      if (buffer.length >= MAX_BUFFER) void flush();
      else scheduleFlush();
    } catch {
      /* analytics must never break the app */
    }
  },

  /** Convenience wrappers. */
  screen(route?: string) {
    Analytics.track("app.screen.viewed", { route });
  },
  search(payload: {
    raw: string;
    normalized: string;
    intent?: string;
    zone?: string;
    resultCount: number;
    aiUsed?: boolean;
  }) {
    Analytics.track(payload.resultCount > 0 ? "search.command.submitted" : "search.command.no_result", {
      metadata: {
        // raw is hashed length only — never store the user's literal text
        raw_length: payload.raw.length,
        normalized_query: payload.normalized,
        intent: payload.intent ?? null,
        zone: payload.zone ?? null,
        result_count: payload.resultCount,
        ai_used: !!payload.aiUsed,
      },
      serviceArea: "search",
    });
  },
  flushNow: flush,
};

export type { EventName };