import { useEffect, useSyncExternalStore } from "react";
import {
  type FlagKey,
  getFlag,
  getPublicWalletLabel,
  isPublicWalletEnabled,
  isOmSandboxActive,
  loadFeatureFlags,
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
 * Convenience hook for the Orange Money First pivot. Returns `true` when
 * the public CHOP Wallet UI should be shown, `false` when it is archived
 * behind the flag. The internal ledger is never affected.
 */
export function usePublicWalletEnabled(): boolean {
  return useFlag("wallet_public_enabled");
}

/** OM checkout master gate. */
export function useOmCheckoutEnabled(): boolean {
  return useFlag("om_checkout_enabled");
}

/** Envoyer v1 (parcel / document delivery) gate. Server enforces it too. */
export function useEnvoyerEnabled(): boolean {
  return useFlag("envoyer_enabled");
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

/** Returns "OM Wallet" when public wallet is archived, else "ChopWallet". */
export function usePublicWalletLabel(): string {
  const publicOn = usePublicWalletEnabled();
  return publicOn ? "ChopWallet" : "OM Wallet";
}

/** Canonical public-payment product name — prefer over `usePublicWalletLabel` in new code. */
export function usePublicPaymentProductName(): string {
  return usePublicWalletLabel();
}

/** Public-payment tile subtitle (reactive to the same flag). */
export function usePublicPaymentProductSubtitle(): string {
  const publicOn = usePublicWalletEnabled();
  return publicOn
    ? "Solde CHOPCHOP · recharges et paiements"
    : "Vos paiements Orange Money, vérifications et remboursements.";
}

export {
  isPublicWalletEnabled,
  isOmSandboxActive,
  getPublicWalletLabel,
  publicPaymentProductName,
  publicPaymentProductSubtitle,
  loadFeatureFlags,
};