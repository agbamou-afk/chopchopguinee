/**
 * WONGO — central brand source of truth.
 * All user-facing product names, taglines, and palette anchors live here.
 * Imported across UI surfaces so a future rebrand is a single-file change.
 *
 * WONGO comes from W'ONKHAI ("Let's go"), blended with GO.
 */

import wordmark from "@/assets/brand/wongo-wordmark.png";
import icon from "@/assets/brand/wongo-icon.png";

export const BRAND = {
  appName: "WONGO",
  legalName: "WONGO GUINEE LTD",
  walletName: "WONGO Wallet",
  payName: "WONGO Pay",
  marketplaceName: "WONGO Marché",
  foodName: "WONGO Repas",
  deliveryName: "WONGO delivery",
  missionName: "WONGO mission",
  brandLine: "W'ONKHAI. LET'S GO.",
  tagline: "One platform. Every move.",
  descriptor: "Urban movement • commerce • logistics • payments",
  domain: "wongo.app",
  socialHandle: "@WongoApp",
  securedBy: "Secured by WONGO Pay",
  trackedBy: "Mission suivie par WONGO",
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
