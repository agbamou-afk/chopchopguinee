/**
 * WONGO — district operations registry.
 *
 * Single source of truth for district metadata: human name, slug, color
 * token, optional center coordinates, optional operating status. Kept
 * intentionally lightweight — districts are operational cells, not themes.
 */
import type { LatLng } from "@/lib/maps/geo";
import {
  CHOP_DISTRICTS,
  type ChopDistrict,
  communeFor,
  detectDistrictInText,
} from "@/lib/maps/zones";

export type DistrictStatus = "active" | "soon" | "paused";

export interface DistrictMeta {
  name: ChopDistrict;
  slug: string;
  /** Tailwind color token suffix (e.g. "emerald", "saffron"). All map to
   *  existing CHOP brand HSL tokens via the `district-*` utility classes
   *  defined in index.css. */
  tone:
    | "emerald"
    | "saffron"
    | "ember"
    | "violet"
    | "ocean"
    | "graphite"
    | "mint"
    | "sand"
    | "sun"
    | "plum"
    | "clay";
  center?: LatLng;
  status: DistrictStatus;
}

export const DISTRICTS: DistrictMeta[] = [
  { name: "Kaloum",     slug: "kaloum",     tone: "graphite", center: { lat: 9.510, lng: -13.706 }, status: "active" },
  { name: "Dixinn",     slug: "dixinn",     tone: "ocean",    center: { lat: 9.570, lng: -13.665 }, status: "active" },
  { name: "Madina",     slug: "madina",     tone: "saffron",  center: { lat: 9.538, lng: -13.673 }, status: "active" },
  { name: "Matam",      slug: "matam",      tone: "ember",    center: { lat: 9.550, lng: -13.640 }, status: "active" },
  { name: "Hamdallaye", slug: "hamdallaye", tone: "sun",      center: { lat: 9.578, lng: -13.642 }, status: "active" },
  { name: "Kipé",       slug: "kipe",       tone: "emerald",  center: { lat: 9.605, lng: -13.640 }, status: "active" },
  { name: "Ratoma",     slug: "ratoma",     tone: "mint",     center: { lat: 9.635, lng: -13.640 }, status: "active" },
  { name: "Lambanyi",   slug: "lambanyi",   tone: "plum",     center: { lat: 9.618, lng: -13.598 }, status: "active" },
  { name: "Cosa",       slug: "cosa",       tone: "violet",   center: { lat: 9.620, lng: -13.620 }, status: "active" },
  { name: "Sonfonia",   slug: "sonfonia",   tone: "sand",     center: { lat: 9.637, lng: -13.570 }, status: "active" },
  { name: "Matoto",     slug: "matoto",     tone: "clay",     center: { lat: 9.605, lng: -13.550 }, status: "active" },
];

const BY_NAME = new Map(DISTRICTS.map((d) => [d.name, d]));
const BY_SLUG = new Map(DISTRICTS.map((d) => [d.slug, d]));

export function getDistrict(nameOrSlug?: string | null): DistrictMeta | null {
  if (!nameOrSlug) return null;
  return BY_NAME.get(nameOrSlug as ChopDistrict) ?? BY_SLUG.get(nameOrSlug.toLowerCase()) ?? null;
}

/** Resolve a district from a coordinate, address text, or known name. */
export function resolveDistrict(input: {
  point?: LatLng | null;
  text?: string | null;
  name?: string | null;
}): DistrictMeta | null {
  if (input.name) {
    const hit = getDistrict(input.name);
    if (hit) return hit;
  }
  if (input.point) {
    const hit = communeFor(input.point);
    if (hit) return getDistrict(hit);
  }
  if (input.text) {
    const hit = detectDistrictInText(input.text);
    if (hit) return getDistrict(hit);
  }
  return null;
}

/** Tailwind utility class fragments. Kept minimal — chips, badges only. */
export function districtChipClasses(tone: DistrictMeta["tone"]): string {
  return `district-chip district-chip--${tone}`;
}

export { CHOP_DISTRICTS };
export type { ChopDistrict };