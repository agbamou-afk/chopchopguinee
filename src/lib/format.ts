/**
 * CHOP CHOP — formatting helpers.
 * Money is always rendered with non-breaking spaces and the GNF suffix.
 * Example: formatGNF(2500000) → "2 500 000 GNF"
 */

const NBSP = "\u00A0";

export function formatGNF(amount: number | bigint | null | undefined): string {
  if (amount === null || amount === undefined) return `0${NBSP}GNF`;
  const n = typeof amount === "bigint" ? Number(amount) : amount;
  if (!Number.isFinite(n)) return `0${NBSP}GNF`;
  const rounded = Math.round(n);
  const abs = Math.abs(rounded).toString();
  // Group thousands with NBSP from the right
  const grouped = abs.replace(/\B(?=(\d{3})+(?!\d))/g, NBSP);
  const sign = rounded < 0 ? "-" : "";
  return `${sign}${grouped}${NBSP}GNF`;
}

export function formatGNFShort(amount: number | bigint | null | undefined): string {
  const n = typeof amount === "bigint" ? Number(amount) : (amount ?? 0);
  if (!Number.isFinite(n)) return `0${NBSP}GNF`;
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return `${(n / 1_000_000).toFixed(abs >= 10_000_000 ? 0 : 1)}M${NBSP}GNF`;
  if (abs >= 1_000) return `${(n / 1_000).toFixed(abs >= 10_000 ? 0 : 1)}k${NBSP}GNF`;
  return formatGNF(n);
}