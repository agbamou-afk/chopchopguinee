/**
 * Node 4 — Marché R13: durable offline BASKET DRAFT.
 *
 * PRODUCT LAW — NO OFFLINE ECONOMIC AUTHORITY.
 * A draft is an *intention*: store, listing ids, quantities, and the customer's
 * destination words. It may be composed with no network at all. It carries a
 * cached unit price ONLY so the UI can tell the customer "le prix a changé"
 * after revalidation — that cached number is never a total, never a promise and
 * never sent as authority. Money, stock and availability are decided by the
 * server at revalidation and frozen at commitment.
 */

const KEY = "chop.marche.basket.draft.v1";
const MAX_LINES = 20;
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

export type MarcheLocationSource = "gps" | "manual_pin" | "saved_place" | "typed";

export interface MarcheDestinationDraft {
  /** Free-text area / address as typed by the customer. */
  label?: string | null;
  /** Landmark prose — how Conakry actually navigates ("près du marché Madina"). */
  landmark?: string | null;
  /** Courier instructions ("portail bleu, appeler à l'arrivée"). */
  instructions?: string | null;
  lat?: number | null;
  lng?: number | null;
  /** How the point (if any) was obtained. The server decides what it is worth. */
  source?: MarcheLocationSource | null;
}

export interface MarcheDraftLine {
  listingId: string;
  qty: number;
  offerId?: string | null;
  title?: string | null;
  /** Last price SEEN. Drift evidence only — never a total. */
  cachedUnitPriceGnf?: number | null;
}

export interface MarcheBasketDraft {
  storeId: string;
  storeName?: string | null;
  lines: MarcheDraftLine[];
  destination: MarcheDestinationDraft;
  updatedAt: number;
}

function store(): Storage | null {
  try {
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    return null;
  }
}

const clampQty = (q: number) => Math.max(1, Math.min(100, Math.floor(Number(q) || 1)));
const trim = (s: unknown, max: number): string | null => {
  const v = typeof s === "string" ? s.trim() : "";
  return v ? v.slice(0, max) : null;
};

/** Normalises anything (including hand-edited storage) into a safe draft. */
export function normalizeDraft(raw: unknown): MarcheBasketDraft | null {
  const d = raw as Partial<MarcheBasketDraft> | null;
  if (!d || typeof d.storeId !== "string" || !d.storeId) return null;
  const lines = Array.isArray(d.lines) ? d.lines : [];
  const seen = new Set<string>();
  const clean: MarcheDraftLine[] = [];
  for (const l of lines) {
    if (!l || typeof l.listingId !== "string" || !l.listingId) continue;
    if (seen.has(l.listingId)) continue;
    seen.add(l.listingId);
    clean.push({
      listingId: l.listingId,
      qty: clampQty(l.qty),
      offerId: typeof l.offerId === "string" && l.offerId ? l.offerId : null,
      title: trim(l.title, 160),
      cachedUnitPriceGnf:
        typeof l.cachedUnitPriceGnf === "number" && Number.isFinite(l.cachedUnitPriceGnf)
          ? Math.max(0, Math.round(l.cachedUnitPriceGnf))
          : null,
    });
    if (clean.length >= MAX_LINES) break;
  }
  if (clean.length === 0) return null;
  const dst = (d.destination ?? {}) as MarcheDestinationDraft;
  const src = dst.source;
  return {
    storeId: d.storeId,
    storeName: trim(d.storeName, 120),
    lines: clean,
    destination: {
      label: trim(dst.label, 200),
      landmark: trim(dst.landmark, 200),
      instructions: trim(dst.instructions, 300),
      lat: typeof dst.lat === "number" && Number.isFinite(dst.lat) ? dst.lat : null,
      lng: typeof dst.lng === "number" && Number.isFinite(dst.lng) ? dst.lng : null,
      source:
        src === "gps" || src === "manual_pin" || src === "saved_place" || src === "typed" ? src : null,
    },
    updatedAt: typeof d.updatedAt === "number" ? d.updatedAt : Date.now(),
  };
}

export function loadBasketDraft(): MarcheBasketDraft | null {
  const ls = store();
  if (!ls) return null;
  try {
    const raw = ls.getItem(KEY);
    if (!raw) return null;
    const d = normalizeDraft(JSON.parse(raw));
    if (!d) return null;
    if (Date.now() - d.updatedAt > MAX_AGE_MS) {
      ls.removeItem(KEY);
      return null;
    }
    return d;
  } catch {
    return null;
  }
}

export function saveBasketDraft(draft: MarcheBasketDraft): MarcheBasketDraft | null {
  const clean = normalizeDraft({ ...draft, updatedAt: Date.now() });
  if (!clean) return null;
  try {
    store()?.setItem(KEY, JSON.stringify(clean));
  } catch {
    /* quota or private mode — the in-memory basket still works */
  }
  return clean;
}

export function clearBasketDraft(): void {
  try {
    store()?.removeItem(KEY);
  } catch {
    /* ignore */
  }
}

/**
 * True when the draft mentions a destination the courier can actually use.
 * Deliberately permissive: a landmark alone is a legitimate Conakry address.
 */
export function hasUsableDestination(d: MarcheDestinationDraft | null | undefined): boolean {
  if (!d) return false;
  return Boolean(d.landmark || d.label || (d.lat != null && d.lng != null));
}
