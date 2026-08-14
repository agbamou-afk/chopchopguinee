/**
 * Node 3 / R9 — durable Repas checkout idempotency key.
 *
 * `repas_order_create` is idempotent only when the SAME `client_request_id` is
 * replayed for the SAME cart. A key that lives only in React state is lost on
 * reload, tab crash or remount — exactly the situations where the commit
 * outcome is unknown — which is how a customer ends up with two orders.
 *
 * The key is therefore persisted, scoped to the intent fingerprint (restaurant
 * + cart lines + fulfillment + tender). It is cleared only once the order is
 * known to exist server-side, or when the customer abandons the checkout.
 */

const STORAGE_KEY = "chopchop.repas.checkout.request";

/** RFC-4122 v4 uuid, with a safe fallback when `crypto.randomUUID` is absent. */
export function newRepasRequestUuid(): string {
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

export interface RepasCheckoutIntent {
  restaurantId: string;
  fulfillment: string;
  paymentMethod: string;
  lines: { menuItemId: string; qty: number }[];
}

/** Stable fingerprint of the commitment. Line order must not change the key. */
export function repasIntentKey(intent: RepasCheckoutIntent): string {
  const lines = [...intent.lines]
    .map((l) => `${l.menuItemId}:${l.qty}`)
    .sort()
    .join(",");
  return [intent.restaurantId, intent.fulfillment, intent.paymentMethod, lines].join("|");
}

interface Persisted {
  key: string;
  id: string;
}

function read(): Persisted | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const p = JSON.parse(raw) as Persisted;
    return p && typeof p.key === "string" && typeof p.id === "string" ? p : null;
  } catch {
    return null;
  }
}

function write(p: Persisted | null) {
  try {
    if (p) localStorage.setItem(STORAGE_KEY, JSON.stringify(p));
    else localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* private mode / quota: the in-memory key still protects this session */
  }
}

let memory: Persisted | null = null;

/**
 * Same uuid for every retry of the same intent — including after a reload.
 * A materially different cart gets a fresh uuid, so a changed order is never
 * silently swallowed by the server replay guard.
 */
export function repasRequestIdFor(intent: RepasCheckoutIntent): string {
  const key = repasIntentKey(intent);
  const current = memory ?? read();
  if (current && current.key === key) {
    memory = current;
    return current.id;
  }
  const next: Persisted = { key, id: newRepasRequestUuid() };
  memory = next;
  write(next);
  return next.id;
}

/** Called once the order is known to exist server-side, or on abandonment. */
export function clearRepasRequestId(): void {
  memory = null;
  write(null);
}

/** The pending key, if a commitment attempt was interrupted before resolution. */
export function pendingRepasRequestId(): string | null {
  const current = memory ?? read();
  return current?.id ?? null;
}
