/**
 * Adapter registry — provider id → adapter implementation.
 * Adding MTN later means appending one entry here; nothing else
 * in the wallet/admin layer needs to change.
 */
import type { PaymentProvider } from "../types";
import type { PaymentProviderAdapter } from "./types";
import { orangeMoneyAdapter } from "./orangeMoney";

const ADAPTERS: Partial<Record<PaymentProvider, PaymentProviderAdapter>> = {
  orange_money: orangeMoneyAdapter,
};

export function getProviderAdapter(p: PaymentProvider): PaymentProviderAdapter | null {
  return ADAPTERS[p] ?? null;
}

export function listProviderAdapters(): PaymentProviderAdapter[] {
  return Object.values(ADAPTERS).filter((a): a is PaymentProviderAdapter => !!a);
}

export { orangeMoneyAdapter };