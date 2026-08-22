/**
 * PASS 2 — FEATURE FLAGS AS CUSTOMER PRODUCT-EXPOSURE SOURCE OF TRUTH.
 *
 * One declarative map from canonical customer action id -> exposure flag.
 * Law (owner-approved):
 *  - Flag OFF => the entry is NOT rendered in customer discovery/launch
 *    surfaces. No "Bientôt disponible" card, no disabled tile, no blank cell.
 *  - Aide/support is NEVER hidden by product flags.
 *  - Only TOP-LEVEL exposure flags appear here. Sub-feature flags
 *    (`om_*`, `driver_balance_gate_enabled`, `envoyer_declared_value_enabled`,
 *    `envoyer_claims_enabled`, map/low-data flags, …) must never hide a whole
 *    discovery entry.
 *  - These are presentation/entry controls mirroring server law; they do NOT
 *    replace server authorization, finance or service gates.
 */
import { useMemo } from "react";
import { type FlagKey, getFlag } from "@/lib/flags/featureFlags";
import { useFeatureFlag, useFlagsReady } from "@/lib/flags/useFeatureFlag";

/** Canonical customer action ids routed by `Index.handleAction` + nav. */
export type ExposureActionId =
  | "moto"
  | "toktok"
  | "auto"
  | "parcel"
  | "food"
  | "market"
  | "wallet"
  | "scan"
  | "merchant"
  | "driver"
  | "help";

/**
 * Action -> flags that expose it. `any: true` means at least one flag is
 * enough (Chop Pay: canonical `chop_pay_enabled` OR legacy alias
 * `wallet_public_enabled`). `[]` means always exposed (support).
 */
type ExposureRule = { flags: FlagKey[]; any?: boolean };

export const SERVICE_EXPOSURE_RULES: Record<ExposureActionId, ExposureRule> = {
  moto: { flags: ["service_moto_enabled"] },
  toktok: { flags: ["service_toktok_enabled"] },
  auto: { flags: ["taxi"] },
  parcel: { flags: ["envoyer_enabled"] },
  food: { flags: ["service_repas_enabled"] },
  market: { flags: ["service_marche_enabled"] },
  // Public payment product: exposed only when the PUBLIC Chop Pay/wallet
  // product is on. Provider/OM readiness (`om_*`) never controls the tile.
  wallet: { flags: ["chop_pay_enabled", "wallet_public_enabled"], any: true },
  scan: { flags: ["service_scan_enabled"] },
  merchant: { flags: ["merchant_recruitment_enabled"] },
  driver: { flags: ["driver_recruitment_enabled"] },
  // Support is a safety surface, never product-gated.
  help: { flags: [] },
};

/** Aliases used by legacy call sites of the central action router. */
const ACTION_ALIASES: Record<string, ExposureActionId> = {
  send: "wallet",
  support: "help",
  envoyer: "parcel",
  repas: "food",
  marche: "market",
};

export function resolveExposureAction(action: string): ExposureActionId | null {
  if (action in SERVICE_EXPOSURE_RULES) return action as ExposureActionId;
  return ACTION_ALIASES[action] ?? null;
}

function evaluate(rule: ExposureRule, read: (k: FlagKey) => boolean): boolean {
  if (rule.flags.length === 0) return true;
  return rule.any ? rule.flags.some(read) : rule.flags.every(read);
}

/**
 * Synchronous exposure truth from the shared flag cache. Used by the central
 * action router (bypass guard) where a hook is not available.
 * Unknown / non-product actions (`services`, `orders`, …) stay exposed.
 */
export function isActionExposed(action: string): boolean {
  const id = resolveExposureAction(action);
  if (!id) return true;
  return evaluate(SERVICE_EXPOSURE_RULES[id], getFlag);
}

export type ServiceExposure = {
  /** True once live flag rows resolved — gate first paint on this. */
  ready: boolean;
  /** Exposure truth for a canonical action id (or alias). */
  isExposed: (action: string) => boolean;
  /** Filter helper preserving source ordering. */
  filter: <T>(items: T[], key: (item: T) => string) => T[];
};

/**
 * Single reusable exposure hook for every customer discovery surface.
 * Subscribes to the one existing flag store — no second subsystem.
 */
export function useServiceExposure(): ServiceExposure {
  const ready = useFlagsReady();
  const moto = useFeatureFlag("service_moto_enabled");
  const toktok = useFeatureFlag("service_toktok_enabled");
  const taxi = useFeatureFlag("taxi");
  const envoyer = useFeatureFlag("envoyer_enabled");
  const repas = useFeatureFlag("service_repas_enabled");
  const marche = useFeatureFlag("service_marche_enabled");
  const scan = useFeatureFlag("service_scan_enabled");
  const chopPay = useFeatureFlag("chop_pay_enabled");
  const legacyWallet = useFeatureFlag("wallet_public_enabled");
  const merchantRecruit = useFeatureFlag("merchant_recruitment_enabled");
  const driverRecruit = useFeatureFlag("driver_recruitment_enabled");

  return useMemo(() => {
    const values: Record<ExposureActionId, boolean> = {
      moto,
      toktok,
      auto: taxi,
      parcel: envoyer,
      food: repas,
      market: marche,
      wallet: chopPay || legacyWallet,
      scan,
      merchant: merchantRecruit,
      driver: driverRecruit,
      help: true,
    };
    const isExposed = (action: string) => {
      const id = resolveExposureAction(action);
      return id ? values[id] : true;
    };
    return {
      ready,
      isExposed,
      filter: <T,>(items: T[], key: (item: T) => string) => items.filter((i) => isExposed(key(i))),
    };
  }, [ready, moto, toktok, taxi, envoyer, repas, marche, scan, chopPay, legacyWallet, merchantRecruit, driverRecruit]);
}

/** Recruitment route guards. */
export function useMerchantRecruitmentExposed(): boolean {
  return useFeatureFlag("merchant_recruitment_enabled");
}

export function useDriverRecruitmentExposed(): boolean {
  return useFeatureFlag("driver_recruitment_enabled");
}
