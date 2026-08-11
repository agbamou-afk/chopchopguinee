import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";

const read = (p: string) => readFileSync(`${process.cwd()}/${p}`, "utf8");

/**
 * Slice 8 hard rule: cancellation amounts come from exactly one server
 * calculator. No React/TypeScript percentage or basis arithmetic is allowed.
 * These are source-level guards so a regression is caught in CI.
 */
describe("Slice 8 — cancellation UI truth guards", () => {
  const lib = read("src/lib/finance/cancellation.ts");
  const dialog = read("src/components/finance/CancellationConfirmDialog.tsx");
  const debts = read("src/components/finance/CancellationDebtPanel.tsx");
  const pkg = read("src/components/envoyer/PackageDeliveries.tsx");
  const chopPay = read("src/components/chopPay/ChopPayOrderPanel.tsx");
  const trip = read("src/components/trip/RealtimeTripScreen.tsx");

  const NO_FEE_MATH = [
    /\*\s*0\.0?[0-9]+/, // * 0.05 / * 0.10
    /\/\s*10000/, // bps division
    /fee_bps\s*[*/]/, // deriving an amount from bps
    /basis_gnf\s*[*/]/, // deriving an amount from the basis
  ];

  it("the client layer only calls the canonical quote RPC", () => {
    expect(lib).toContain('rpc("cancellation_quote"');
    expect(lib).toContain('rpc("customer_cancellation_debts_overview"');
    expect(lib).toContain('rpc("customer_cancellation_debt_repay"');
    for (const re of NO_FEE_MATH) expect(lib).not.toMatch(re);
  });

  it("the confirmation dialog renders server quote fields verbatim", () => {
    expect(dialog).toContain("useCancellationQuote");
    expect(dialog).toContain("quote.fee_gnf");
    expect(dialog).toContain("quote.basis_gnf");
    expect(dialog).toContain("quote.refundable_gnf");
    for (const re of NO_FEE_MATH) expect(dialog).not.toMatch(re);
  });

  it("the debt panel never subtracts or infers the restriction", () => {
    expect(debts).toContain("data.outstanding_total_gnf");
    expect(debts).toContain("cash_orders_allowed");
    expect(debts).not.toMatch(/outstanding_total_gnf\s*[-+]/);
    for (const re of NO_FEE_MATH) expect(debts).not.toMatch(re);
  });

  it("every customer cancellation surface uses the shared dialog", () => {
    for (const src of [pkg, chopPay, trip]) {
      expect(src).toContain("CancellationConfirmDialog");
      for (const re of NO_FEE_MATH) expect(src).not.toMatch(re);
    }
  });

  it("the Envoyer surface no longer confirms with a locally built message", () => {
    expect(pkg).not.toContain("window.confirm");
    expect(pkg).not.toContain("previewPackageCancel");
  });
});