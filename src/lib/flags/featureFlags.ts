/**
 * Lightweight feature-flag runtime cache.
 *
 * Reads `public.feature_flags` once at boot and exposes a synchronous
 * accessor so UI code can branch without turning every render into an
 * async query. Non-critical: on failure we fall back to safe defaults.
 *
 * This is intentionally NOT a full flag system — it exists to let us
 * archive the public CHOP Wallet without hardcoding the decision in
 * a dozen files. Add new flags to `DEFAULTS` and `KNOWN_FLAGS`.
 */
import { supabase } from "@/integrations/supabase/client";

export type FlagKey =
  | "wallet_public_enabled"
  | "chop_pay_enabled"
  | "om_topup_enabled"
  | "om_direct_checkout_enabled"
  | "driver_balance_gate_enabled"
  | "envoyer_enabled"
  | "envoyer_declared_value_enabled"
  | "envoyer_claims_enabled"
  | "om_checkout_enabled"
  | "om_provider_mode"
  | "om_ride_checkout_enabled"
  | "om_repas_checkout_enabled"
  | "om_marche_checkout_enabled"
  | "om_sandbox_enabled"
  | "om_environment"
  | "taxi"
  // PASS 2 — customer product-exposure flags. Presentation/entry law only:
  // OFF means the entry is NOT rendered in customer discovery surfaces
  // (no placeholder, no disabled card). They never replace server law.
  | "service_moto_enabled"
  | "service_toktok_enabled"
  | "service_repas_enabled"
  | "service_marche_enabled"
  | "service_scan_enabled"
  | "merchant_recruitment_enabled"
  | "driver_recruitment_enabled";

const DEFAULTS: Record<FlagKey, boolean> = {
  // Orange Money First pivot: public CHOP Wallet UI is archived until
  // explicitly re-enabled by a Super Admin from /admin/flags.
  wallet_public_enabled: false,
  // Chop Pay revival (chop-pay-ledger-revival). `chop_pay_enabled` is the
  // canonical switch for the public payment product; `wallet_public_enabled`
  // is kept as a backwards-compatible alias for existing call sites.
  chop_pay_enabled: false,
  // Orange Money is RETAINED as a manual cash-in / top-up rail.
  om_topup_enabled: true,
  // Orange Money as a DIRECT customer checkout method is ARCHIVED.
  om_direct_checkout_enabled: false,
  // Driver operating-balance gate (commission reserve + mission collateral).
  driver_balance_gate_enabled: false,
  // Envoyer v1 — parcel/document delivery. Server RPCs enforce this same
  // flag; the client value is only used to pick the honest UI state.
  envoyer_enabled: false,
  // Slice 6 — Envoyer declared value / attestation / evidence engine.
  envoyer_declared_value_enabled: false,
  // Slice 6 — Envoyer claims (custody dispute) lifecycle.
  envoyer_claims_enabled: false,
  // Orange Money Checkout Orchestration — all off by default. Each slice
  // is landable behind its own flag; downstream code stays on legacy paths
  // until the flag is flipped in /admin/flags.
  om_checkout_enabled: false,
  om_provider_mode: false, // false = manual operator verification (launch default)
  om_ride_checkout_enabled: false,
  om_repas_checkout_enabled: false,
  om_marche_checkout_enabled: false,
  // Sandbox ecosystem — sandbox test references (OM-SBX-*) are only
  // honored when both env=sandbox and om_sandbox_enabled=true. Production
  // defaults keep both off so real customers can never trigger fake flows.
  om_sandbox_enabled: false,
  om_environment: false, // false = production, true = sandbox/staging
  // Node 2 — Taxi (`auto`) passenger-car rides. OFF until real approved
  // Taxi drivers exist; the tile renders an honest "bientôt" state.
  taxi: false,
  // PASS 2 exposure flags — default ON because these products are already
  // live. The live `public.feature_flags` rows are the source of truth.
  service_moto_enabled: true,
  service_toktok_enabled: true,
  service_repas_enabled: true,
  service_marche_enabled: true,
  service_scan_enabled: true,
  merchant_recruitment_enabled: true,
  driver_recruitment_enabled: true,
};

const KNOWN_FLAGS: FlagKey[] = [
  "wallet_public_enabled",
  "chop_pay_enabled",
  "om_topup_enabled",
  "om_direct_checkout_enabled",
  "driver_balance_gate_enabled",
  "envoyer_enabled",
  "envoyer_declared_value_enabled",
  "envoyer_claims_enabled",
  "om_checkout_enabled",
  "om_provider_mode",
  "om_ride_checkout_enabled",
  "om_repas_checkout_enabled",
  "om_marche_checkout_enabled",
  "om_sandbox_enabled",
  "om_environment",
  "taxi",
  "service_moto_enabled",
  "service_toktok_enabled",
  "service_repas_enabled",
  "service_marche_enabled",
  "service_scan_enabled",
  "merchant_recruitment_enabled",
  "driver_recruitment_enabled",
];

/** Exported for tests/admin tooling: the exact flag keys the client reads. */
export const CLIENT_KNOWN_FLAGS: readonly FlagKey[] = KNOWN_FLAGS;
export const CLIENT_FLAG_DEFAULTS: Readonly<Record<FlagKey, boolean>> = DEFAULTS;

let cache: Record<FlagKey, boolean> = { ...DEFAULTS };
let loaded = false;
let inflight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function emit() {
  for (const cb of listeners) {
    try { cb(); } catch { /* ignore */ }
  }
}

async function fetchAndApply(): Promise<void> {
  try {
    const { data, error } = await supabase
      .from("feature_flags")
      .select("key, enabled")
      .in("key", KNOWN_FLAGS);
    if (!error && Array.isArray(data)) {
      const next: Record<FlagKey, boolean> = { ...DEFAULTS };
      for (const row of data as { key: string; enabled: boolean }[]) {
        if ((KNOWN_FLAGS as string[]).includes(row.key)) {
          next[row.key as FlagKey] = !!row.enabled;
        }
      }
      cache = next;
    }
  } catch {
    // keep last known truth (or DEFAULTS on cold boot)
  } finally {
    loaded = true;
    inflight = null;
    emit();
  }
}

export async function loadFeatureFlags(): Promise<void> {
  if (loaded) return;
  if (inflight) return inflight;
  inflight = fetchAndApply();
  return inflight;
}

/**
 * Force a re-read of `public.feature_flags` into the SAME shared cache.
 * Used by (a) the God-Admin surface right after an audited toggle RPC and
 * (b) Realtime (re)subscription recovery so missed changes reconcile.
 */
export async function refreshFeatureFlags(): Promise<void> {
  if (inflight) return inflight;
  inflight = fetchAndApply();
  return inflight;
}


export function getFlag(key: FlagKey): boolean {
  return cache[key];
}

export function isPublicWalletEnabled(): boolean {
  // Chop Pay is the canonical flag; the legacy key stays as an alias so a
  // rollback of either switch never corrupts balances or history.
  return getFlag("chop_pay_enabled") || getFlag("wallet_public_enabled");
}

/** Canonical customer-facing product name for the money surface. */
export const CHOP_PAY_NAME = "Chop Pay";

/** Orange Money as a direct checkout method — archived by default. */
export function isOmDirectCheckoutEnabled(): boolean {
  return getFlag("om_direct_checkout_enabled");
}

/** Orange Money retained as the manual top-up / cash-in rail. */
export function isOmTopupEnabled(): boolean {
  return getFlag("om_topup_enabled");
}

/** Driver operating-balance eligibility gate. */
export function isDriverBalanceGateEnabled(): boolean {
  return getFlag("driver_balance_gate_enabled");
}

/**
 * Centralized public label for the money/payments surface. When the
 * public CHOP Wallet is archived (Orange Money First pivot), all public
 * tiles / nav labels must read "OM Wallet" instead of "ChopWallet".
 */
export function getPublicWalletLabel(): string {
  return CHOP_PAY_NAME;
}

/**
 * Public-facing name for the customer payment product. Alias of
 * `getPublicWalletLabel` — kept as the canonical import for new call
 * sites so intent (public payment product) is obvious. Do not hardcode
 * "ChopWallet" / "OM Wallet" in components.
 */
export function publicPaymentProductName(): string {
  return getPublicWalletLabel();
}

/** Short subtitle shown under the public payment tile. */
export function publicPaymentProductSubtitle(): string {
  return isPublicWalletEnabled()
    ? "Votre solde CHOPCHOP · recharges, envois et paiements"
    : "Paiement en espèces · rechargement Orange Money bientôt activé.";
}

/**
 * Sandbox environment resolver. Sandbox is only "on" when the deployment
 * is explicitly tagged sandbox AND the sandbox master flag is enabled.
 * Ordinary production users must never see sandbox affordances.
 */
export function isOmSandboxActive(): boolean {
  return getFlag("om_environment") && getFlag("om_sandbox_enabled");
}

export function subscribeFlags(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function flagsLoaded(): boolean {
  return loaded;
}

/**
 * PASS 2 anti-flicker primitive. Customer discovery surfaces must not paint
 * a possibly-disabled product tile before the live flag rows have resolved.
 * Same single store — no second flag subsystem.
 */
export function flagsReady(): boolean {
  return loaded;
}

/** Test-only: reset the runtime cache so a suite can simulate cold load. */
export function __resetFeatureFlagsForTests(next?: Partial<Record<FlagKey, boolean>>, ready = true): void {
  cache = { ...DEFAULTS, ...(next ?? {}) };
  loaded = ready;
  inflight = null;
  emit();
}
/* ------------------------------------------------------------------ *
 * LIVE PROPAGATION — Realtime on public.feature_flags
 *
 * A God-Admin toggle must reach already-open customer UIs without a
 * reload. This is the SAME store: Realtime only writes into `cache`
 * and emits, so every `useFeatureFlag` / `useServiceExposure` consumer
 * rerenders. Realtime loss never breaks the UI: cached truth stays and
 * a resubscribe triggers a full refresh so missed changes reconcile.
 * ------------------------------------------------------------------ */

type FlagRealtimePayload = {
  eventType?: string;
  new?: { key?: string; enabled?: boolean } | null;
  old?: { key?: string; enabled?: boolean } | null;
};

function isKnown(key: unknown): key is FlagKey {
  return typeof key === "string" && (KNOWN_FLAGS as string[]).includes(key);
}

/**
 * Deterministically apply one `feature_flags` row change to the cache.
 * Exported for tests. Unknown keys are ignored; DELETE (or a row that no
 * longer carries a value) reverts to the compiled DEFAULT for that key.
 */
export function applyFlagRealtimeEvent(payload: FlagRealtimePayload): boolean {
  const evt = (payload?.eventType ?? "").toUpperCase();
  const key = payload?.new?.key ?? payload?.old?.key;
  if (!isKnown(key)) return false;

  const nextValue =
    evt === "DELETE" || payload?.new == null || typeof payload.new.enabled !== "boolean"
      ? DEFAULTS[key]
      : !!payload.new.enabled;

  if (cache[key] === nextValue) return false;
  cache = { ...cache, [key]: nextValue };
  emit();
  return true;
}

let flagChannel: { unsubscribe?: () => void } | null = null;
let sawDisconnect = false;

/** Exported for tests: current subscription status handler. */
export function handleFlagChannelStatus(status: string): void {
  const s = (status ?? "").toUpperCase();
  if (s === "CHANNEL_ERROR" || s === "TIMED_OUT" || s === "CLOSED") {
    sawDisconnect = true;
    return;
  }
  if (s === "SUBSCRIBED" && sawDisconnect) {
    sawDisconnect = false;
    // Reconnect: reconcile anything missed while the socket was down.
    void refreshFeatureFlags();
  }
}

/**
 * Idempotent. Safe across HMR / remounts / duplicate boot calls: only one
 * effective channel is ever created.
 */
export function initFeatureFlagsRealtime(): () => void {
  if (flagChannel) return teardownFeatureFlagsRealtime;
  try {
    const channel = supabase
      .channel("feature-flags-live")
      .on(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        "postgres_changes" as any,
        { event: "*", schema: "public", table: "feature_flags" },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (payload: any) => { applyFlagRealtimeEvent(payload as FlagRealtimePayload); },
      )
      .subscribe((status: string) => handleFlagChannelStatus(status));
    flagChannel = channel as unknown as { unsubscribe?: () => void };
  } catch {
    flagChannel = null; // Realtime unavailable — cached truth still governs.
  }
  return teardownFeatureFlagsRealtime;
}

export function teardownFeatureFlagsRealtime(): void {
  const ch = flagChannel;
  flagChannel = null;
  sawDisconnect = false;
  if (!ch) return;
  try { supabase.removeChannel(ch as never); } catch { /* ignore */ }
}

/** Test-only: is a channel currently held by the store? */
export function __flagsRealtimeActiveForTests(): boolean {
  return flagChannel !== null;
}
