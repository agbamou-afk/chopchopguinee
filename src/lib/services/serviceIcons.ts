import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import envoyerIcon from "@/assets/icons/envoyer.png";
import scannerIcon from "@/assets/icons/scanner.png";
import walletIcon from "@/assets/icons/wallet.png";

/**
 * CANONICAL CHOPCHOP ICON TYPOLOGY — single source of truth.
 *
 * Family A ("service") — transactional products the customer buys:
 *   Moto, Bonbonna, Taxi, Envoyer, Repas, Marché, Chop Pay, Scanner.
 *   Rendered as branded raster art inside a primary-tinted rounded-square chip.
 *
 * Family B ("entry") — entry / utility actions (Devenir marchand, Devenir
 *   chauffeur, Aide). Rendered as a neutral CIRCULAR chip with a Lucide glyph
 *   at stroke 1.75. Deliberately different so it never reads as a product.
 *
 * No surface may hardcode its own asset map or optical tuning: import from
 * here so ServicesView / QuickActions / PrimaryActionGrid cannot drift.
 */

export type ServiceIconId =
  | "moto"
  | "toktok"
  | "auto"
  | "parcel"
  | "food"
  | "market"
  | "wallet"
  | "scan";

export type IconFamily = "service" | "entry";

/** Branded artwork per canonical service id. `auto` (Taxi) has no art yet. */
export const SERVICE_ICON_ASSETS: Partial<Record<ServiceIconId, string>> = {
  moto: motoIcon,
  toktok: toktokIcon,
  parcel: envoyerIcon,
  food: repasIcon,
  market: marcheIcon,
  wallet: walletIcon,
  scan: scannerIcon,
};

/**
 * Per-icon optical tuning. Each artwork has a slightly different inner
 * bounding box, so we balance the family by adjusting scale + nudges inside
 * the shared holder. Values tuned visually, not mathematically.
 */
export type IconTuning = { scale: number; x: number; y: number };

export const SERVICE_ICON_TUNING: Record<ServiceIconId, IconTuning> = {
  moto:   { scale: 1.57, x: 0, y: 0 },
  toktok: { scale: 1.5,  x: 0, y: 0 },
  auto:   { scale: 1,    x: 0, y: 0 },
  food:   { scale: 1.59, x: 0, y: 0 },
  market: { scale: 1.49, x: 0, y: 0 },
  parcel: { scale: 1.42, x: 0, y: 0 },
  wallet: { scale: 1.45, x: 0, y: 0 },
  scan:   { scale: 1.42, x: 0, y: 0 },
};

export const DEFAULT_ICON_TUNING: IconTuning = { scale: 1, x: 0, y: 0 };

export function getServiceIconTuning(id: string): IconTuning {
  return SERVICE_ICON_TUNING[id as ServiceIconId] ?? DEFAULT_ICON_TUNING;
}

export function getServiceIconAsset(id: string): string | undefined {
  return SERVICE_ICON_ASSETS[id as ServiceIconId];
}

/**
 * PASS 1 placeholder registry: transactional services that legitimately have
 * NO branded artwork yet and therefore render a Lucide glyph *inside the
 * Family-A chip*. Never borrow another service's art for these.
 *
 * TODO(brand): commission `taxi.png` and remove `auto` from this list.
 */
export const SERVICE_GLYPH_PLACEHOLDERS: ServiceIconId[] = ["auto"];

export function isServiceGlyphPlaceholder(id: string): boolean {
  return SERVICE_GLYPH_PLACEHOLDERS.includes(id as ServiceIconId);
}

/** Shared chip geometry — the visual contract both families are built on. */
export const SERVICE_CHIP_CLASS =
  "w-11 h-11 rounded-xl bg-primary/10 ring-1 ring-primary/15 flex items-center justify-center overflow-hidden shrink-0";

export const ENTRY_CHIP_CLASS =
  "w-11 h-11 rounded-full bg-muted/60 ring-1 ring-border flex items-center justify-center overflow-hidden shrink-0";

export const SERVICE_GLYPH_CLASS = "w-6 h-6 text-primary";
export const ENTRY_GLYPH_CLASS = "w-5 h-5 text-muted-foreground";

/** Lucide stroke width mandated by DESIGN_SYSTEM.md. */
export const UTILITY_STROKE_WIDTH = 1.75;
