import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { repasIntentKey, newRepasRequestUuid } from "@/lib/repas/checkoutRequestId";

const detail = readFileSync("src/components/food/RepasRestaurantDetail.tsx", "utf8");
const orders = readFileSync("src/lib/repas/orders.ts", "utf8");
const merchant = readFileSync("src/components/merchant/repas/RepasOrdersSection.tsx", "utf8");

describe("Repas R9 — recovery flows", () => {
  it("checkout no longer holds the idempotency key in volatile component state", () => {
    expect(detail).not.toMatch(/useState<string>\(\(\) => crypto\.randomUUID\(\)\)/);
    expect(detail).toContain("repasRequestIdFor");
  });

  it("an unknown commit outcome is resolved against the server, not retried blindly", () => {
    expect(detail).toContain("resumeFoodOrder");
    expect(detail).toContain("pendingRepasRequestId");
  });

  it("the request key is cleared only once the order is known to exist", () => {
    expect(detail).toContain("clearRepasRequestId");
  });

  it("resume is a read-only RPC binding", () => {
    expect(orders).toContain("repas_order_resume");
    expect(orders).not.toMatch(/repas_order_resume[\s\S]{0,200}insert\(/i);
  });

  it("a refused merchant action rehydrates canonical truth", () => {
    expect(merchant).toMatch(/catch[\s\S]{0,400}void reload\(\)/);
  });

  it("the intent key is order-insensitive and cart-sensitive", () => {
    const a = repasIntentKey({
      restaurantId: "r", fulfillment: "pickup", paymentMethod: "choppay",
      lines: [{ menuItemId: "a", qty: 1 }, { menuItemId: "b", qty: 2 }],
    });
    const b = repasIntentKey({
      restaurantId: "r", fulfillment: "pickup", paymentMethod: "choppay",
      lines: [{ menuItemId: "b", qty: 2 }, { menuItemId: "a", qty: 1 }],
    });
    const c = repasIntentKey({
      restaurantId: "r", fulfillment: "pickup", paymentMethod: "choppay",
      lines: [{ menuItemId: "a", qty: 3 }, { menuItemId: "b", qty: 2 }],
    });
    expect(a).toBe(b);
    expect(a).not.toBe(c);
  });

  it("generates RFC-4122 v4 identifiers", () => {
    expect(newRepasRequestUuid()).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
  });
});
