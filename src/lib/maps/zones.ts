import type { LatLng } from './geo';

/**
 * CHOPCHOP — district registry.
 * Conakry communes + commonly referenced neighbourhoods. Kept lightweight:
 * we only need a name to label rides, missions, receipts and merchant cards.
 */
export const CHOP_DISTRICTS = [
  'Kaloum', 'Dixinn', 'Matam', 'Ratoma', 'Matoto',
  'Kipé', 'Hamdallaye', 'Madina', 'Lambanyi', 'Cosa', 'Sonfonia',
] as const;
export type ChopDistrict = (typeof CHOP_DISTRICTS)[number];

const COMMUNES: Array<{ name: ChopDistrict; bbox: [number, number, number, number] }> = [
  { name: 'Kaloum', bbox: [-13.726, 9.490, -13.685, 9.530] },
  { name: 'Madina', bbox: [-13.685, 9.520, -13.660, 9.555] },
  { name: 'Dixinn', bbox: [-13.685, 9.555, -13.640, 9.585] },
  { name: 'Matam', bbox: [-13.660, 9.530, -13.620, 9.570] },
  { name: 'Hamdallaye', bbox: [-13.660, 9.560, -13.625, 9.595] },
  { name: 'Kipé', bbox: [-13.660, 9.590, -13.620, 9.620] },
  { name: 'Ratoma', bbox: [-13.700, 9.580, -13.580, 9.690] },
  { name: 'Lambanyi', bbox: [-13.620, 9.595, -13.575, 9.640] },
  { name: 'Cosa', bbox: [-13.640, 9.605, -13.600, 9.635] },
  { name: 'Sonfonia', bbox: [-13.600, 9.610, -13.540, 9.665] },
  { name: 'Matoto', bbox: [-13.620, 9.560, -13.480, 9.650] },
];
export function communeFor(p: LatLng): ChopDistrict | null {
  for (const c of COMMUNES) {
    const [minLng, minLat, maxLng, maxLat] = c.bbox;
    if (p.lng >= minLng && p.lng <= maxLng && p.lat >= minLat && p.lat <= maxLat) return c.name;
  }
  return null;
}

/** Alias to the new naming used across the Spatial Intelligence layer. */
export const districtFor = communeFor;

/** "Kaloum → Ratoma" style label. Falls back gracefully when unknown. */
export function formatDistrictPair(
  from?: LatLng | null,
  to?: LatLng | null,
): string | null {
  const a = from ? communeFor(from) : null;
  const b = to ? communeFor(to) : null;
  if (a && b && a !== b) return `${a} → ${b}`;
  if (a && b && a === b) return a;
  return a || b || null;
}

/** Normalize a free-text address to a known district when one is mentioned. */
export function detectDistrictInText(text?: string | null): ChopDistrict | null {
  if (!text) return null;
  const lower = text.toLowerCase();
  for (const d of CHOP_DISTRICTS) {
    if (lower.includes(d.toLowerCase())) return d;
  }
  return null;
}
