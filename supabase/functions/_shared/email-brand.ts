/// <reference types="npm:@types/react@18.3.1" />

// CHOP CHOP — shared brand tokens for all email templates
// (auth + transactional). Kept as plain values so React Email can inline them.
// Source of truth: src/index.css.

export const BRAND = {
  name: "CHOP CHOP",
  legalName: "CHOP GUINEE LTD",
  tagline: "L'infrastructure de confiance pour la mobilité et le commerce en Guinée.",
  url: "https://chopchopguinee.com",
  logoUrl: "https://chopchopguinee.com/favicon.png",
  supportEmail: "support@chopchopguinee.com",
  supportPhone: "+224 621 00 00 00",
  address: "Conakry, République de Guinée",
} as const;

export const COLORS = {
  // Brand
  green: "#1ba34d",        // primary — hsl(138, 64%, 39%)
  greenDark: "#157a39",
  gold: "#f2c744",         // secondary — hsl(45, 90%, 62%)
  goldDark: "#c89c1f",
  red: "#dc4036",          // destructive — hsl(2, 75%, 56%)

  // Neutrals (Material 3 inspired, soft)
  bg: "#ffffff",
  surface: "#fafafa",
  surfaceMuted: "#f4f5f7",
  border: "#e8eaed",
  borderStrong: "#d8dadc",
  text: "#1a1a1a",
  textMuted: "#5f6368",
  textFaint: "#9aa0a6",

  // Status
  successBg: "#e6f4ec",
  successFg: "#0f6b35",
  warningBg: "#fef5d8",
  warningFg: "#7a5a00",
  errorBg: "#fde7e5",
  errorFg: "#9a261d",
  infoBg: "#e8f0fe",
  infoFg: "#1a4480",
} as const;

export const FONT_STACK =
  "'Poppins', 'Google Sans', 'Segoe UI', Roboto, -apple-system, BlinkMacSystemFont, Arial, sans-serif";

export const RADIUS = { sm: "8px", md: "12px", lg: "16px", xl: "20px" } as const;

// Money formatting (GNF, French locale)
export function formatGNF(value: number | string): string {
  const n = typeof value === "string" ? Number(value) : value;
  if (!Number.isFinite(n)) return `${value} GNF`;
  return `${Math.round(n).toLocaleString("fr-FR").replace(/\u202F/g, "\u00A0")}\u00A0GNF`;
}

export function formatDateFr(input: string | Date): string {
  const d = typeof input === "string" ? new Date(input) : input;
  if (Number.isNaN(d.getTime())) return String(input);
  return d.toLocaleString("fr-FR", {
    day: "2-digit",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}