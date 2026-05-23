/**
 * Display helpers for CHOPCHOP internal references (WNG-YYYY-NNNNNN).
 * Generated server-side via the `next_wongo_reference()` SQL function.
 */

const WNG_RE = /^WNG-\d{4}-\d{6}$/;

export function isWongoReference(ref: string | null | undefined): boolean {
  return !!ref && WNG_RE.test(ref);
}

export function formatReference(ref: string | null | undefined): string {
  if (!ref) return "—";
  return ref;
}