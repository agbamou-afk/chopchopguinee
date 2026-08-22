import { useEffect, useSyncExternalStore } from "react";
import {
  type FlagKey,
  getFlag,
  getPublicWalletLabel,
  isPublicWalletEnabled,
  isOmSandboxActive,
  isOmDirectCheckoutEnabled,
  isOmTopupEnabled,
  isDriverBalanceGateEnabled,
  CHOP_PAY_NAME,
  loadFeatureFlags,
  flagsReady,
  subscribeFlags,
  publicPaymentProductName,
  publicPaymentProductSubtitle,
} from "./featureFlags";

function useFlag(key: FlagKey): boolean {
  useEffect(() => { void loadFeatureFlags(); }, []);
  return useSyncExternalStore(
    subscribeFlags,
    () => getFlag(key),
    () => getFlag(key),
  );
}

export function useFeatureFlag(key: FlagKey): boolean {
  return useFlag(key);
}

/**
 * True once the live `feature_flags` rows have resolved (or definitively
 * failed and fallen back to defaults). Customer discovery surfaces gate
 * their first paint on this so a disabled product is never flashed.
 */
export function useFlagsReady(): boolean {
  useEffect(() => { void loadFeatureFlags(); }, []);
  return useSyncExternalStore(subscribeFlags, flagsReady, flagsReady);
}

/**
 * Convenience hook for the Orange Money First pivot. Returns `true` when
 * the public CHOP Wallet UI should be shown, `false` when it is archived
 * behind the flag. The internal ledger is never affected.
 */
export function usePublicWalletEnabled(): boolean {
  const chopPay = useFlag("chop_pay_enabled");
  const legacy = useFlag("wallet_public_enabled");
  return chopPay || legacy;
}

/** Canonical Chop Pay availability hook (alias of `usePublicWalletEnabled`). */
export function useChopPayEnabled(): boolean {
  return usePublicWalletEnabled();
}

/** ARCHIVED rail: Orange Money as a direct customer checkout method. */
export function useOmDirectCheckoutEnabled(): boolean {
  return useFlag("om_direct_checkout_enabled");
}

/** RETAINED rail: Orange Money manual cash-in / top-up. */
export function useOmTopupEnabled(): boolean {
  return useFlag("om_topup_enabled");
}

/** Driver operating-balance eligibility gate. */
export function useDriverBalanceGateEnabled(): boolean {
  return useFlag("driver_balance_gate_enabled");
}

/**
 * OM DIRECT checkout master gate. Since the Chop Pay pivot this requires
 * BOTH the legacy rail flag and the explicit archive-override flag
 * `om_direct_checkout_enabled`, so no public surface can regress into
 * offering Orange Money as a direct payment method.
 */
export function useOmCheckoutEnabled(): boolean {
  const legacy = useFlag("om_checkout_enabled");
  const direct = useFlag("om_direct_checkout_enabled");
  return legacy && direct;
}

/** Envoyer v1 (parcel / document delivery) gate. Server enforces it too. */
export function useEnvoyerEnabled(): boolean {
  return useFlag("envoyer_enabled");
}

/** Node 2 — Taxi (`auto`) rides. OFF until approved Taxi drivers exist. */
export function useTaxiEnabled(): boolean {
  return useFlag("taxi");
}

/** Slice 6 — declared value + attestation + photo evidence engine. */
export function useEnvoyerDeclaredValueEnabled(): boolean {
  return useFlag("envoyer_declared_value_enabled");
}

/** Slice 6 — customer claims lifecycle (custody disputes). */
export function useEnvoyerClaimsEnabled(): boolean {
  return useFlag("envoyer_claims_enabled");
}

/** true = provider webhooks trusted; false = manual verification (launch default). */
export function useOmProviderAutomated(): boolean {
  return useFlag("om_provider_mode");
}

/** true only when the deployment is a sandbox env AND sandbox is enabled. */
export function useOmSandboxActive(): boolean {
  const env = useFlag("om_environment");
  const sbx = useFlag("om_sandbox_enabled");
  return env && sbx;
}

export function usePublicWalletLabel(): string {
  return CHOP_PAY_NAME;
}

/** Canonical public-payment product name — prefer over `usePublicWalletLabel` in new code. */
export function usePublicPaymentProductName(): string {
  return usePublicWalletLabel();
}

/** Public-payment tile subtitle (reactive to the same flag). */
export function usePublicPaymentProductSubtitle(): string {
  const publicOn = usePublicWalletEnabled();
  return publicOn
    ? "Votre solde CHOPCHOP · recharges, envois et paiements"
    : "Paiement en espèces · rechargement Orange Money bientôt activé.";
}

export {
  isPublicWalletEnabled,
  isOmSandboxActive,
  isOmDirectCheckoutEnabled,
  isOmTopupEnabled,
  isDriverBalanceGateEnabled,
  CHOP_PAY_NAME,
  getPublicWalletLabel,
  publicPaymentProductName,
  publicPaymentProductSubtitle,
  loadFeatureFlags,
  flagsReady,
};