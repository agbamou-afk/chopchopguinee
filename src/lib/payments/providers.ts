/**
 * Provider registry — the single source of truth for how CHOPCHOP renders
 * payment providers. Adding a future rail (e.g. MTN Money, bank settlement)
 * means registering it here, not editing top-up sheets or receipts.
 */
import type { PaymentProvider } from "./types";

export type ProviderKind = "mobile_money" | "cash" | "manual" | "internal" | "agent";

export interface ProviderConfig {
  id: PaymentProvider;
  label: string;
  kind: ProviderKind;
  /** Whether this provider is wired for live use today. */
  liveEnabled: boolean;
  supports: { topup: boolean; payment: boolean; payout: boolean };
}

export const PAYMENT_PROVIDERS: Record<PaymentProvider, ProviderConfig> = {
  orange_money: { id: "orange_money", label: "Orange Money", kind: "mobile_money",
                  liveEnabled: true,  supports: { topup: true,  payment: true,  payout: true  } },
  mtn_money:    { id: "mtn_money",    label: "MTN Money",    kind: "mobile_money",
                  liveEnabled: false, supports: { topup: true,  payment: true,  payout: true  } },
  cash:         { id: "cash",         label: "Espèces",       kind: "cash",
                  liveEnabled: true,  supports: { topup: false, payment: true,  payout: true  } },
  manual:       { id: "manual",       label: "Manuel (admin)", kind: "manual",
                  liveEnabled: true,  supports: { topup: true,  payment: false, payout: true  } },
  internal:     { id: "internal",     label: "Interne CHOPCHOP",  kind: "internal",
                  liveEnabled: true,  supports: { topup: false, payment: true,  payout: false } },
  agent:        { id: "agent",        label: "Agent CHOPCHOP",    kind: "agent",
                  liveEnabled: true,  supports: { topup: true,  payment: false, payout: false } },
};

export function providerLabel(p: PaymentProvider | string | null | undefined): string {
  if (!p) return "Interne";
  return PAYMENT_PROVIDERS[p as PaymentProvider]?.label ?? "Interne";
}

export function liveTopupProviders(): ProviderConfig[] {
  return Object.values(PAYMENT_PROVIDERS).filter((p) => p.liveEnabled && p.supports.topup);
}