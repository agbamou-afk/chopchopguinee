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
  livraison: "Livraison",
  food: "Repas",
};

/** Primary service label shown to users. Falls back to the raw value. */
export function rideModeLabel(mode: string | null | undefined): string {
  if (!mode) return "";
  return RIDE_MODE_LABEL[mode] ?? mode;
}

/** Short descriptive subtitle per mode (optional UI). */
export const RIDE_MODE_SUBTITLE: Record<string, string> = {
  moto: "Moto-taxi rapide à Conakry",
  toktok: "Tricycle pour vos déplacements",
};
