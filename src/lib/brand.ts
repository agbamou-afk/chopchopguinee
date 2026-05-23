/**
 * CHOPCHOP — central brand source of truth.
 * All user-facing product names, taglines, and palette anchors live here.
 * Imported across UI surfaces so a future rebrand is a single-file change.
 *
 * CHOPCHOP is the consumer-facing brand. CHOPCHOP may remain reserved as a
 * future internal/corporate/infrastructure concept; do not surface it in UI.
 */

// Asset file names kept stable to avoid breaking imports; the displayed
// artwork is the CHOPCHOP wordmark/icon, fed through BrandLogo for theming.
import wordmark from "@/assets/logo.png";
import icon from "@/assets/logo.png";

export const BRAND = {
  appName: "CHOPCHOP",
  legalName: "CHOPCHOP GUINEE LTD",
  walletName: "ChopWallet",
  payName: "ChopPay",
  marketplaceName: "Chop Marché",
  foodName: "Chop Repas",
  deliveryName: "Chop Courier",
  missionName: "Chop mission",
  brandLine: "CHOPCHOP. LET'S GO.",
  tagline: "One platform. Every move.",
  descriptor: "Urban movement • commerce • logistics • payments",
  domain: "wongo.app",
  socialHandle: "@ChopChopApp",
  securedBy: "Secured by ChopPay",
  trackedBy: "Mission suivie par CHOPCHOP",
  assets: {
    wordmark,
    icon,
  },
  colors: {
    charcoal: "#0F1412",
    green: "#118338",
    yellow: "#F4B400",
    red: "#CE1126",
    cream: "#F7F5EF",
  },
} as const;

export type BrandConfig = typeof BRAND;
