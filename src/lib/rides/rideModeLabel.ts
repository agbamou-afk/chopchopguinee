/**
 * Canonical customer-facing labels for ride/transport modes.
 *
 * IMPORTANT: internal identifiers (DB enum `ride_mode`, fare keys, analytics
 * events, routes, driver capabilities) keep the historical value `toktok`.
 * This module is the ONLY place that maps those internal values to the
 * user-visible name, which is now `Bonbonna` (local-market rename, 2026-08).
 */

export const RIDE_MODE_LABEL: Record<string, string> = {
  moto: "Moto",
  toktok: "Bonbonna",
  auto: "Taxi",
  livraison: "Livraison",
  food: "Repas",
};

/** Bookable passenger-ride products (internal identifiers). */
export type RideProductMode = "moto" | "toktok" | "auto";

/** Primary service label shown to users. Falls back to the raw value. */
export function rideModeLabel(mode: string | null | undefined): string {
  if (!mode) return "";
  return RIDE_MODE_LABEL[mode] ?? mode;
}

/** Short descriptive subtitle per mode (optional UI). */
export const RIDE_MODE_SUBTITLE: Record<string, string> = {
  moto: "Moto-taxi rapide à Conakry",
  toktok: "Tricycle pour vos déplacements",
  auto: "Voiture avec chauffeur à Conakry",
};

/**
 * Full service title used in headers, offers, notifications and receipts.
 * Always prefer this over hardcoded "Course Moto".
 */
export function rideServiceTitle(mode: string | null | undefined): string {
  if (!mode) return "Course";
  if (mode === "food") return "Livraison Repas";
  if (mode === "livraison") return "Livraison";
  return `Course ${rideModeLabel(mode)}`;
}

/**
 * Product differentiation shown to the customer before booking.
 * Bonbonna (tricycle) is not a "bigger moto": it carries more people and
 * cargo, and it is the sheltered option when it rains.
 */
export interface RideModeProduct {
  /** Room on board, described qualitatively (never a passenger count). */
  capacity: string;
  /** What can realistically travel with the passenger. */
  cargo: string;
  /** Weather suitability, which matters a lot in Conakry. */
  weather: string;
  /** One-line positioning statement. */
  positioning: string;
}

export const RIDE_MODE_PRODUCT: Record<string, RideModeProduct> = {
  moto: {
    capacity: "Trajet individuel",
    cargo: "Sac à main ou petit sac à dos",
    weather: "À éviter sous la pluie",
    positioning: "Le plus rapide dans les embouteillages",
  },
  toktok: {
    capacity: "Plus de place à bord",
    cargo: "Bagages, courses et cartons",
    weather: "Abrité de la pluie et du soleil",
    positioning: "Plus de place, plus de bagages, à l'abri",
  },
  auto: {
    capacity: "Voiture fermée, trajet en famille ou entre collègues",
    cargo: "Valises, cartons et achats volumineux dans le coffre",
    weather: "Totalement à l'abri de la pluie, du soleil et de la poussière",
    positioning: "Le trajet le plus confortable et le plus discret",
  },
};
