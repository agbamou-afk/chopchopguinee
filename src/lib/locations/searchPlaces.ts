import { CONAKRY_PLACES, type GazetteerPlace, type PlaceCategory } from './conakryGazetteer';
import { normalize, similarity } from './searchNormalize';

export interface PlaceSearchResult {
  id: string;
  name: string;
  district: string | null;
  commune: string | null;
  category: PlaceCategory;
  confidence: GazetteerPlace['confidence'];
  latitude: number | null;
  longitude: number | null;
  source: 'gazetteer';
  score: number;
}

const CATEGORY_PRIORITY: Record<PlaceCategory, number> = {
  km_marker: 6, neighborhood: 5, district: 5, admin: 4, market: 4,
  airport: 4, transport: 3, hospital: 3, school: 3, landmark: 3,
  road: 2, restaurant: 2, store: 2, other: 1,
};

// Pre-build a normalized index once.
interface IndexedPlace { place: GazetteerPlace; normName: string; normAliases: string[]; tokens: Set<string> }
const INDEX: IndexedPlace[] = CONAKRY_PLACES.map((p) => {
  const normName = normalize(p.name);
  const normAliases = p.aliases.map(normalize);
  const tokens = new Set<string>(normName.split(' ').concat(normAliases.flatMap((a) => a.split(' '))));
  return { place: p, normName, normAliases, tokens };
});

/**
 * Forgiving local search across the Conakry gazetteer.
 *
 * Ranking (highest first):
 *   1. exact normalized name
 *   2. exact normalized alias
 *   3. starts-with name / alias
 *   4. contains name / alias
 *   5. fuzzy similarity (bigram + token Jaccard)
 *   6. category priority tiebreak
 */
export function searchConakryPlaces(
  query: string,
  opts: { limit?: number; commune?: string | null; minScore?: number } = {},
): PlaceSearchResult[] {
  const limit = opts.limit ?? 8;
  const minScore = opts.minScore ?? 0.45;
  const q = normalize(query);
  if (!q) return [];

  const scored: Array<PlaceSearchResult & { _tiebreak: number }> = [];
  for (const entry of INDEX) {
    const { place, normName, normAliases } = entry;
    let s = 0;
    if (normName === q) s = 1.0;
    else if (normAliases.includes(q)) s = 0.98;
    else if (normName.startsWith(q)) s = 0.90;
    else if (normAliases.some((a) => a.startsWith(q))) s = 0.88;
    else if (normName.includes(q)) s = 0.78;
    else if (normAliases.some((a) => a.includes(q))) s = 0.74;
    else {
      const best = Math.max(similarity(q, normName), ...normAliases.map((a) => similarity(q, a)));
      s = best;
    }
    if (s < minScore) continue;
    // Boost when commune matches caller hint
    if (opts.commune && place.commune && normalize(opts.commune) === normalize(place.commune)) s += 0.05;
    const tiebreak = CATEGORY_PRIORITY[place.category] ?? 0;
    scored.push({
      id: place.id,
      name: place.name,
      district: place.district,
      commune: place.commune,
      category: place.category,
      confidence: place.confidence,
      latitude: place.latitude,
      longitude: place.longitude,
      source: 'gazetteer',
      score: s,
      _tiebreak: tiebreak,
    });
  }
  scored.sort((a, b) => (b.score - a.score) || (b._tiebreak - a._tiebreak));
  return scored.slice(0, limit).map(({ _tiebreak, ...rest }) => rest);
}

/** Pretty French label for category chip. */
export function categoryLabel(c: PlaceCategory): string {
  switch (c) {
    case 'km_marker': return 'Point kilométrique';
    case 'neighborhood': return 'Quartier';
    case 'district': return 'Quartier';
    case 'admin': return 'Commune';
    case 'market': return 'Marché';
    case 'airport': return 'Aéroport';
    case 'transport': return 'Transport';
    case 'hospital': return 'Hôpital';
    case 'school': return 'École';
    case 'landmark': return 'Point de repère';
    case 'road': return 'Route';
    case 'restaurant': return 'Restaurant';
    case 'store': return 'Boutique';
    default: return 'Lieu';
  }
}

/** French confidence label for UI. */
export function confidenceLabel(c: GazetteerPlace['confidence']): string | null {
  if (c === 'exact') return null;
  if (c === 'approximate') return 'Position approximative';
  return 'Zone uniquement';
}