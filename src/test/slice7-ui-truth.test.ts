import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";

const read = (p: string) => readFileSync(new URL(`../../${p}`, import.meta.url), "utf8");

/**
 * Slice 7 hard rule: no product surface may reconstruct a financial amount.
 * These are source-level guards so a regression is caught in CI.
 */
describe("Slice 7 — ledger-truth UI guards", () => {
  const wallet = read("src/components/views/WalletView.tsx");
  const receipt = read("src/components/wallet/TransactionReceiptSheet.tsx");

  it("WalletView sends the server available amount to SendMoneySheet", () => {
    expect(wallet).toContain("const available = overview?.available_gnf ?? 0;");
    expect(wallet).toContain("available={available}");
    expect(wallet).not.toMatch(/balance_gnf\s*-\s*wallet\.held_gnf/);
  });

  it("WalletView history comes from customer_finance_history", () => {
    expect(wallet).toContain("useCustomerFinanceHistory");
    expect(wallet).toContain("ev.amount_gnf");
    expect(wallet).not.toContain("filteredTransactions");
  });

  it("receipt sheet reads customer_receipt and has no raw-transaction fallback", () => {
    expect(receipt).toContain("fetchCustomerReceipt");
    expect(receipt).toContain("receipt.amount_gnf");
    expect(receipt).toContain("Reçu indisponible");
    expect(receipt).not.toContain("WalletTransaction");
  });
});
