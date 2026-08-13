/**
 * Node 0 closeout: retry idempotency for the ride commitment RPC.
 *
 * `ride_request_create` is idempotent only when the SAME uuid is replayed, so
 * the client must persist one uuid per booking commitment attempt and reuse it
 * across ambiguous network failures. The id is reset only when the ride is
 * actually created, when the booking sheet is abandoned, or when the booking
 * intent materially changes (mode / pickup / destination / payment choice).
 */

/** RFC-4122 v4 uuid. Falls back to a valid uuid when `crypto.randomUUID` is absent. */
export function newRequestUuid(): string {
  const c = typeof crypto !== "undefined" ? crypto : undefined;
  if (c && typeof c.randomUUID === "function") return c.randomUUID();

  const bytes = new Uint8Array(16);
  if (c && typeof c.getRandomValues === "function") {
    c.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10x
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export interface BookingIntent {
  mode: string;
  pickupCoords: [number, number];
  destCoords: [number, number];
  paymentMode: "chop_pay" | "cash";
}

/** Stable fingerprint of the commitment the customer is about to make. */
export function bookingIntentKey(intent: BookingIntent): string {
  return [
    intent.mode,
    intent.pickupCoords[0],
    intent.pickupCoords[1],
    intent.destCoords[0],
    intent.destCoords[1],
    intent.paymentMode,
  ].join("|");
}

export interface BookingRequestIdStore {
  /** Same uuid for repeated retries of the same intent; new uuid when the intent changes. */
  idFor(intent: BookingIntent): string;
  /** Call after successful authoritative creation or on booking abandonment. */
  reset(): void;
}

export function createBookingRequestIdStore(): BookingRequestIdStore {
  let key: string | null = null;
  let id: string | null = null;
  return {
    idFor(intent) {
      const k = bookingIntentKey(intent);
      if (key !== k || id === null) {
        key = k;
        id = newRequestUuid();
      }
      return id;
    },
    reset() {
      key = null;
      id = null;
    },
  };
}
