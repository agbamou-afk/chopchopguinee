import { describe, it, expect } from "vitest";
import {
  REPAS_CUSTODY_BOUNDARY_LABEL,
  repasPaymentStateLabel,
  repasReceiptTotalLabel,
  repasTrackingLabel,
} from "@/lib/repas/tracking";

describe("R7 — ready label makes no custody claim", () => {
  it("delivery `ready` never says the courier already has the order", () => {
    const label = repasTrackingLabel({ state: "ready", fulfillment: "delivery" } as never);
    expect(label).not.toMatch(/remise au coursier/i);
    expect(label).not.toMatch(/coursier/i);
    expect(label).toBe("Prête au restaurant");
  });

  it("only post-handoff states may communicate courier possession / en route", () => {
    const out = repasTrackingLabel({ state: "out_for_delivery", fulfillment: "delivery" } as never);
    expect(out).toMatch(/coursier/i);
    for (const state of ["placed", "confirmed", "preparing", "ready"] as const) {
      expect(repasTrackingLabel({ state, fulfillment: "delivery" } as never)).not.toMatch(/en route/i);
    }
  });

  it("pickup `ready` stays a restaurant-side claim", () => {
    expect(repasTrackingLabel({ state: "ready", fulfillment: "pickup" } as never)).not.toMatch(/coursier/i);
  });
});

describe("R7 — custody boundary labels", () => {
  const actual = ["restaurant_to_courier", "courier_to_customer", "merchant_to_customer_pickup"];
  it("renders the actual R6 boundaries in French, never a raw identifier", () => {
    for (const b of actual) {
      const label = REPAS_CUSTODY_BOUNDARY_LABEL[b];
      expect(label).toBeTruthy();
      expect(label).not.toContain("_");
      expect(label).not.toBe(b);
    }
    expect(REPAS_CUSTODY_BOUNDARY_LABEL.restaurant_to_courier).toBe("Remise au coursier");
    expect(REPAS_CUSTODY_BOUNDARY_LABEL.courier_to_customer).toBe("Remise au client");
    expect(REPAS_CUSTODY_BOUNDARY_LABEL.merchant_to_customer_pickup).toBe("Retrait par le client");
  });

  it("keeps legacy aliases so historical rows never leak snake_case", () => {
    expect(REPAS_CUSTODY_BOUNDARY_LABEL.restaurant_handoff).toBe("Remise au coursier");
    expect(REPAS_CUSTODY_BOUNDARY_LABEL.customer_delivery).toBe("Remise au client");
    expect(REPAS_CUSTODY_BOUNDARY_LABEL.customer_pickup).toBe("Retrait par le client");
  });
});

describe("R7 — canonical payment / total semantics", () => {
  it("labels the total paid only when the engine settled the value", () => {
    expect(
      repasReceiptTotalLabel({ payment_state: "paid", payment_settled: true, payment_rail: "chop_pay" } as never),
    ).toBe("Total payé");
    expect(
      repasReceiptTotalLabel({ payment_state: "collected", payment_settled: true, payment_rail: "cash" } as never),
    ).toBe("Total réglé");
  });

  it("never says paid for authorized, due or cancelled orders", () => {
    for (const s of ["authorized", "due", "released", "cancelled", "disputed", "unknown"] as const) {
      expect(
        repasReceiptTotalLabel({ payment_state: s, payment_settled: false, payment_rail: "chop_pay" } as never),
      ).toBe("Total de la commande");
    }
  });

  it("exposes an honest French payment status for every canonical state", () => {
    expect(repasPaymentStateLabel("paid")).toBe("Payé");
    expect(repasPaymentStateLabel("authorized")).toBe("Autorisé — en cours");
    expect(repasPaymentStateLabel("released")).toBe("Annulé — montant libéré");
    expect(repasPaymentStateLabel("due")).toBe("À régler");
    expect(repasPaymentStateLabel("collected")).toBe("Réglé en espèces");
    expect(repasPaymentStateLabel(null)).toBe("Non confirmé");
    expect(repasPaymentStateLabel("some_future_state")).toBe("Non confirmé");
  });
});
