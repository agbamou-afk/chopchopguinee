/**
 * Node 3 / R11 — durable Conakry destination draft.
 *
 * Conakry addresses are landmark-based and slow to type, and the network drops
 * mid-checkout. Losing the typed destination on a reload is the single most
 * expensive failure in the Repas funnel, so the in-progress destination is
 * persisted locally, per restaurant.
 *
 * This is a CONVENIENCE cache only:
 *  - it never carries prices, totals, fees or any order identity;
 *  - it is never trusted at commit time (the server re-derives everything);
 *  - it is cleared as soon as the order is committed or abandoned.
 */

const STORAGE_KEY = "chopchop.repas.destination.draft";

/** What the client honestly knows about how the point was obtained. */
export type RepasLocationSource = "gps" | "manual_pin" | "typed" | "unspecified";

export interface RepasDestinationDraft {
  restaurantId: string;
  label: string;
  landmark: string;
  instructions: string;
  lat: number | null;
  lng: number | null;
  source: RepasLocationSource;
  savedAt: number;
}

/** A stale draft is worse than no draft: a day-old destination is discarded. */
const MAX_AGE_MS = 24 * 60 * 60 * 1000;

export const EMPTY_DESTINATION_DRAFT: Omit<RepasDestinationDraft, "restaurantId" | "savedAt"> = {
  label: "",
  landmark: "",
  instructions: "",
  lat: null,
  lng: null,
  source: "unspecified",
};

export function readDestinationDraft(restaurantId: string): RepasDestinationDraft | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const d = JSON.parse(raw) as RepasDestinationDraft;
    if (!d || d.restaurantId !== restaurantId) return null;
    if (typeof d.savedAt !== "number" || Date.now() - d.savedAt > MAX_AGE_MS) return null;
    return d;
  } catch {
    return null;
  }
}

export function writeDestinationDraft(
  draft: Omit<RepasDestinationDraft, "savedAt">,
): void {
  try {
    const empty =
      !draft.label.trim() && !draft.landmark.trim() && !draft.instructions.trim() &&
      draft.lat === null && draft.lng === null;
    if (empty) {
      localStorage.removeItem(STORAGE_KEY);
      return;
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...draft, savedAt: Date.now() }));
  } catch {
    /* private mode / quota: the session still holds the值 in React state */
  }
}

export function clearDestinationDraft(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* ignore */
  }
}

/** French, honest labels for the SERVER-derived location quality verdict. */
export const REPAS_LOCATION_QUALITY_LABEL: Record<string, string> = {
  gps_verified: "Position GPS confirmée",
  manually_placed: "Point placé à la main",
  landmark_assisted: "Repère seulement — pas de point GPS",
  approximate: "Position approximative",
  unverifiable: "Position non vérifiable",
};

export function repasLocationQualityLabel(q?: string | null): string | null {
  if (!q) return null;
  return REPAS_LOCATION_QUALITY_LABEL[q] ?? null;
}
