import { describe, expect, it } from "vitest";
import {
  createBookingRequestIdStore,
  newRequestUuid,
  type BookingIntent,
} from "@/lib/rides/bookingRequestId";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

const intent: BookingIntent = {
  mode: "moto",
  pickupCoords: [9.5, -13.7],
  destCoords: [9.6, -13.6],
  paymentMode: "chop_pay",
};

describe("booking request id", () => {
  it("produces a valid v4 uuid even without crypto.randomUUID", () => {
    const original = globalThis.crypto;
    const stub = { getRandomValues: original.getRandomValues.bind(original) };
    Object.defineProperty(globalThis, "crypto", { value: stub, configurable: true });
    try {
      expect(newRequestUuid()).toMatch(UUID_RE);
    } finally {
      Object.defineProperty(globalThis, "crypto", { value: original, configurable: true });
    }
  });

  it("reuses the same id across retries of the same booking intent", () => {
    const store = createBookingRequestIdStore();
    const first = store.idFor(intent);
    const retry = store.idFor(intent);
    expect(retry).toBe(first);
    expect(first).toMatch(UUID_RE);
  });

  it("issues a new id after a successful creation resets the store", () => {
    const store = createBookingRequestIdStore();
    const first = store.idFor(intent);
    store.reset();
    expect(store.idFor(intent)).not.toBe(first);
  });

  it("issues a new id when the intent materially changes", () => {
    const store = createBookingRequestIdStore();
    const first = store.idFor(intent);
    expect(store.idFor({ ...intent, paymentMode: "cash" })).not.toBe(first);
    expect(store.idFor({ ...intent, destCoords: [9.7, -13.5] })).not.toBe(first);
  });
});
