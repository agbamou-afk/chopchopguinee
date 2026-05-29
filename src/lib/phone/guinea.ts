// Guinea (+224) phone normalization & validation helpers.
// Used by signup, profile completion and profile edit forms during the
// CHOPCHOP Guinea pilot. We do NOT enable phone-based auth here; the value
// is only persisted on profiles / user_metadata.

export const GUINEA_DIAL_CODE = "+224";

/** Strip everything except digits. */
function digitsOnly(raw: string): string {
  return (raw ?? "").replace(/\D+/g, "");
}

/**
 * Return only the local part of a Guinea number (no country code, no
 * separators). Accepts inputs like:
 *   "622123456", "622 12 34 56", "622-12-34-56",
 *   "224622123456", "+224622123456", "00224622123456".
 */
export function extractGuineaLocal(raw: string): string {
  let d = digitsOnly(raw);
  if (d.startsWith("00224")) d = d.slice(5);
  else if (d.startsWith("224")) d = d.slice(3);
  return d;
}

/**
 * Guinea mobile numbers are 9 digits (e.g. 6XX XX XX XX).
 * We accept 8–9 digits to stay tolerant of legacy entries, matching
 * the previous app-wide validation tolerance.
 */
export function isValidGuineaLocal(local: string): boolean {
  return /^[0-9]{8,9}$/.test(local);
}

/** Normalize any user input to E.164-style `+224XXXXXXXXX`. */
export function normalizeGuineaPhone(raw: string): string {
  const local = extractGuineaLocal(raw);
  return `${GUINEA_DIAL_CODE}${local}`;
}

/** Pretty display for the local part: "622 12 34 56". */
export function formatGuineaLocal(local: string): string {
  const d = digitsOnly(local);
  if (d.length <= 3) return d;
  if (d.length <= 5) return `${d.slice(0, 3)} ${d.slice(3)}`;
  if (d.length <= 7) return `${d.slice(0, 3)} ${d.slice(3, 5)} ${d.slice(5)}`;
  return `${d.slice(0, 3)} ${d.slice(3, 5)} ${d.slice(5, 7)} ${d.slice(7, 9)}`;
}

export const GUINEA_PHONE_INVALID_MESSAGE =
  "Numéro invalide. Entrez votre numéro guinéen sans l'indicatif +224.";