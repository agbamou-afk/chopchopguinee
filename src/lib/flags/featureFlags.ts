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
  | "om_checkout_enabled"
  | "om_provider_mode"
  | "om_ride_checkout_enabled"
  | "om_repas_checkout_enabled"
  | "om_marche_checkout_enabled"
  | "om_sandbox_enabled"
  | "om_environment";

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
};

const KNOWN_FLAGS: FlagKey[] = [
  "wallet_public_enabled",
  "chop_pay_enabled",
  "om_topup_enabled",
  "om_direct_checkout_enabled",
  "driver_balance_gate_enabled",
  "envoyer_enabled",
  "om_checkout_enabled",
  "om_provider_mode",
  "om_ride_checkout_enabled",
  "om_repas_checkout_enabled",
  "om_marche_checkout_enabled",
  "om_sandbox_enabled",
  "om_environment",
];

let cache: Record<FlagKey, boolean> = { ...DEFAULTS };
let loaded = false;
let inflight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function emit() {
  for (const cb of listeners) {
    try { cb(); } catch { /* ignore */ }
  }
}

export async function loadFeatureFlags(): Promise<void> {
  if (loaded) return;
  if (inflight) return inflight;
  inflight = (async () => {
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
      // keep DEFAULTS
    } finally {
      loaded = true;
      inflight = null;
      emit();
    }
  })();
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