/**
 * Node 4 — Marché R3: durable commitment key for `marche_order_commit`.
 *
 * The server is idempotent only when the SAME client_request_id is replayed
 * with the SAME payload, so the client must persist one key per basket
 * intent and reuse it across retries, reloads and ambiguous network failures.
 * A materially different basket (store, lines, quantities, agreement,
 * destination) must NEVER reuse a key — the server would answer
 * IDEMPOTENCY_CONFLICT.
 */

const STORAGE_PREFIX = "chop.marche.order.key.";

export interface OrderCommitIntent {
  storeId: string;
  lines: { listingId: string; qty: number; offerId?: string | null }[];
  deliveryAddress?: string | null;
  dropoffLat?: number | null;
  dropoffLng?: number | null;
}

/** RFC-4122 v4 uuid, with a safe fallback when `crypto.randomUUID` is absent. */
export function newOrderRequestUuid(): string {
  const c = typeof crypto !== "undefined" ? crypto : undefined;
  if (c && typeof c.randomUUID === "function") return c.randomUUID();
  const bytes = new Uint8Array(16);
  if (c && typeof c.getRandomValues === "function") c.getRandomValues(bytes);
  else for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * Stable fingerprint of the commitment. Mirrors the fields the server hashes,
 * but is only used locally to decide whether a key may be reused. No price,
 * subtotal or fee ever takes part in it — money is server truth.
 */
export function orderIntentKey(intent: OrderCommitIntent): string {
  const lines = [...intent.lines]
    .map((l) => `${l.listingId}:${l.qty}:${l.offerId ?? ""}`)
    .sort()
    .join(",");
  return [
    intent.storeId,
    lines,
    intent.deliveryAddress ?? "",
    intent.dropoffLat ?? "",
    intent.dropoffLng ?? "",
  ].join("|");
}

function readStore(): Storage | null {
  try {
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    return null;
  }
}

export interface OrderRequestIdStore {
  /** Same key while the intent is unchanged; a fresh key when it materially changes. */
  idFor(intent: OrderCommitIntent): string;
  /** Call once the order is authoritatively committed, or when the basket is abandoned. */
  reset(intent?: OrderCommitIntent): void;
}

/**
 * Durable store: survives a reload so a retry after a lost response reuses the
 * same key and the server returns the SAME order instead of creating a second
 * reservation.
 */
export function createOrderRequestIdStore(scope = "default"): OrderRequestIdStore {
  const memory = new Map<string, string>();
  const slot = (k: string) => `${STORAGE_PREFIX}${scope}.${k}`;

  return {
    idFor(intent) {
      const k = orderIntentKey(intent);
      const mem = memory.get(k);
      if (mem) return mem;
      const ls = readStore();
      const persisted = ls?.getItem(slot(k)) ?? null;
      if (persisted) {
        memory.set(k, persisted);
        return persisted;
      }
      const id = newOrderRequestUuid();
      memory.set(k, id);
      try {
        ls?.setItem(slot(k), id);
      } catch {
        /* storage unavailable — in-memory reuse still protects the session */
      }
      return id;
    },
    reset(intent) {
      const ls = readStore();
      if (intent) {
        const k = orderIntentKey(intent);
        memory.delete(k);
        try {
          ls?.removeItem(slot(k));
        } catch {
          /* ignore */
        }
        return;
      }
      for (const k of memory.keys()) {
        try {
          ls?.removeItem(slot(k));
        } catch {
          /* ignore */
        }
      }
      memory.clear();
    },
  };
}
