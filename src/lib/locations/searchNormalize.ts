/**
 * Normalization utilities for Conakry location search. Handles French
 * accents, KM marker variants, and loose user spelling. Always lowercase,
 * always accent-stripped, always single-spaced.
 */

/** Strip diacritics (NFD trick). */
export function stripAccents(s: string): string {
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

/**
 * Normalize "KM 5", "km5", "Km-5", "K M 5", "kilomètre 5", "kilometer 5"
 * to a canonical `km5` token. Inserted before generic normalization so the
 * digit stays glued to the prefix.
 */
function collapseKmTokens(s: string): string {
  return s
    // "kilometre 5" / "kilomètre 5" / "kilometer 5" / "kilometers 5"
    .replace(/\bkilo?m[eè]?tres?\b[\s\-_]*([0-9]+)/gi, 'km$1')
    .replace(/\bkilometers?\b[\s\-_]*([0-9]+)/gi, 'km$1')
    // "k m 5" / "k.m. 5"
    .replace(/\bk[\s\.\-_]*m[\s\.\-_]*([0-9]+)/gi, 'km$1')
    // "km 5" / "km-5" / "km_5"
    .replace(/\bkm[\s\-_]*([0-9]+)/gi, 'km$1');
}

/**
 * Full normalization pipeline. Use this for both the gazetteer index and
 * incoming queries so they line up.
 */
export function normalize(input: string): string {
  if (!input) return '';
  let s = stripAccents(String(input).toLowerCase());
  s = collapseKmTokens(s);
  s = s.replace(/[''`´]/g, '');           // apostrophes
  s = s.replace(/[^a-z0-9\s]+/g, ' ');     // punctuation → space
  s = s.replace(/\s+/g, ' ').trim();
  return s;
}

/**
 * Lightweight similarity (0..1). Uses normalized strings, prefers prefix +
 * substring overlap, and falls back to a token Jaccard. No heavy deps.
 */
export function similarity(a: string, b: string): number {
  const na = normalize(a), nb = normalize(b);
  if (!na || !nb) return 0;
  if (na === nb) return 1;
  if (nb.startsWith(na) || na.startsWith(nb)) return 0.92;
  if (nb.includes(na) || na.includes(nb)) return 0.78;
  // Token Jaccard
  const ta = new Set(na.split(' '));
  const tb = new Set(nb.split(' '));
  let inter = 0;
  ta.forEach((t) => { if (tb.has(t)) inter += 1; });
  const union = new Set([...ta, ...tb]).size;
  const jaccard = union ? inter / union : 0;
  // Character bigram overlap as cheap fuzzy
  const bigrams = (s: string) => {
    const out = new Set<string>();
    for (let i = 0; i < s.length - 1; i++) out.add(s.slice(i, i + 2));
    return out;
  };
  const ba = bigrams(na), bb = bigrams(nb);
  let bi = 0; ba.forEach((g) => { if (bb.has(g)) bi += 1; });
  const bigramScore = (ba.size + bb.size) ? (2 * bi) / (ba.size + bb.size) : 0;
  return Math.max(jaccard, bigramScore * 0.85);
}