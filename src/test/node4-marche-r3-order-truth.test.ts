import { describe, it, expect, beforeEach } from "vitest";
import {
  createOrderRequestIdStore,
  orderIntentKey,
  newOrderRequestUuid,
  type OrderCommitIntent,
} from "@/lib/marche/orderRequestId";
import { translateOrderError, orderDisplayTotalGnf, orderStatusLabel, type MarcheOrder } from "@/lib/marche/orders";

const base: OrderCommitIntent = {
  storeId: "store-1",
  lines: [{ listingId: "l1", qty: 2, offerId: null }],
  deliveryAddress: "Kaloum",
};

describe("Node4 R3 — durable commitment key", () => {
  beforeEach(() => localStorage.clear());

  it("reuses the same key for an unchanged basket", () => {
    const s = createOrderRequestIdStore("t");
    expect(s.idFor(base)).toBe(s.idFor({ ...base, lines: [{ ...base.lines[0] }] }));
  });

  it("survives a reload (durable, not memory-only)", () => {
    const first = createOrderRequestIdStore("t").idFor(base);
    expect(createOrderRequestIdStore("t").idFor(base)).toBe(first);
  });

  it("issues a NEW key when quantity changes", () => {
    const s = createOrderRequestIdStore("t");
    const a = s.idFor(base);
    const b = s.idFor({ ...base, lines: [{ listingId: "l1", qty: 3 }] });
    expect(a).not.toBe(b);
  });

  it("issues a NEW key when the agreement reference changes", () => {
    const s = createOrderRequestIdStore("t");
    expect(s.idFor(base)).not.toBe(s.idFor({ ...base, lines: [{ listingId: "l1", qty: 2, offerId: "o1" }] }));
  });

  it("issues a NEW key after reset (abandoned basket)", () => {
    const s = createOrderRequestIdStore("t");
    const a = s.idFor(base);
    s.reset(base);
    expect(s.idFor(base)).not.toBe(a);
  });

  it("key is order-insensitive across lines", () => {
    const a = orderIntentKey({ storeId: "s", lines: [{ listingId: "a", qty: 1 }, { listingId: "b", qty: 1 }] });
    const b = orderIntentKey({ storeId: "s", lines: [{ listingId: "b", qty: 1 }, { listingId: "a", qty: 1 }] });
    expect(a).toBe(b);
  });

  it("emits uuid-shaped keys", () => {
    expect(newOrderRequestUuid()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it("never encodes money into the idempotency key", () => {
    expect(orderIntentKey(base)).not.toMatch(/gnf|price|total/i);
  });
});

describe("Node4 R3 — refusal translation", () => {
  it.each([
    "INSUFFICIENT_STOCK",
    "SINGLE_STORE_ONLY",
    "IDEMPOTENCY_CONFLICT",
    "CLIENT_PRICE_NOT_ALLOWED",
    "MERCHANT_STORE_REQUIRED",
    "OFFER_NOT_AGREED",
    "SELF_PURCHASE_NOT_ALLOWED",
  ])("maps %s to a customer message", (code) => {
    const msg = translateOrderError(code);
    expect(msg).not.toBe(code);
    expect(msg.length).toBeGreaterThan(3);
  });

  it("passes unknown codes through unchanged", () => {
    expect(translateOrderError("SOME_NEW_CODE")).toBe("SOME_NEW_CODE");
  });
});

describe("Node4 R3 — display truth", () => {
  const order = {
    merchandise_subtotal_gnf: 250000,
    merchant_fee_gnf: null,
    delivery_charge_gnf: null,
    status: "committed",
  } as unknown as MarcheOrder;

  it("displays only the server merchandise subtotal", () => {
    expect(orderDisplayTotalGnf(order)).toBe(250000);
  });

  it("carries no fee or delivery charge in R3", () => {
    expect(order.merchant_fee_gnf).toBeNull();
    expect(order.delivery_charge_gnf).toBeNull();
  });

  it("labels statuses in French", () => {
    expect(orderStatusLabel("committed")).toMatch(/confirm/i);
    expect(orderStatusLabel("cancelled")).toMatch(/Annul/i);
    expect(orderStatusLabel("expired")).toMatch(/Expir/i);
  });
});
