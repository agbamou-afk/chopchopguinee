/**
 * Server-only keyed hashing for account recovery.
 *
 * Every stored value is HMAC-SHA256 keyed with `ACCOUNT_RECOVERY_PEPPER`
 * (an Edge Function secret, never shipped to the browser) and domain-separated
 * by a scope + the user id, which acts as the per-record salt. A plain
 * unkeyed SHA is never used: an attacker with a database dump but no pepper
 * cannot brute-force short answers.
 */

const enc = new TextEncoder();

let cachedKey: CryptoKey | null = null;

async function hmacKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  const pepper = Deno.env.get("ACCOUNT_RECOVERY_PEPPER");
  if (!pepper) throw new Error("missing_pepper");
  cachedKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return cachedKey;
}

function toHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Keyed hash of `value` inside `scope`, salted by `salt` (usually the user id). */
export async function keyedHash(scope: string, salt: string, value: string): Promise<string> {
  const key = await hmacKey();
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${scope}\u0000${salt}\u0000${value}`));
  return toHex(sig);
}

/** Timing-safe hex comparison. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Locale-stable normalization applied before hashing every free-text answer.
 * NFKC → trim → collapse internal whitespace → strip combining marks →
 * lowercase. "  Élan   Bleu " and "elan bleu" therefore match.
 */
export function normalizeAnswer(raw: string): string {
  return raw
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

/** ISO `YYYY-MM-DD`, or null when the input is not a plausible birthdate. */
export function normalizeBirthdate(raw: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec((raw ?? "").trim());
  if (!m) return null;
  const [, y, mo, d] = m;
  const year = Number(y);
  const date = new Date(`${y}-${mo}-${d}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return null;
  if (year < 1900 || date.getTime() > Date.now()) return null;
  return `${y}-${mo}-${d}`;
}

export function normalizeEmail(raw: string): string {
  return (raw ?? "").normalize("NFKC").trim().toLowerCase();
}

/** Crockford-style alphabet: no I, L, O, U — unambiguous when read aloud. */
const KEY_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/**
 * 20 characters from a 32-symbol alphabet = 100 bits of entropy (>= the 80-bit
 * requirement), grouped as `XXXX-XXXX-XXXX-XXXX-XXXX` for readability.
 */
export function generateRecoveryKey(): string {
  const bytes = new Uint8Array(20);
  crypto.getRandomValues(bytes);
  const chars = Array.from(bytes, (b) => KEY_ALPHABET[b % KEY_ALPHABET.length]);
  return [0, 4, 8, 12, 16].map((i) => chars.slice(i, i + 4).join("")).join("-");
}

/** Accepts the key with or without dashes, in any case, with stray spaces. */
export function normalizeRecoveryKey(raw: string): string {
  const compact = (raw ?? "").normalize("NFKC").replace(/[^0-9a-zA-Z]/g, "").toUpperCase();
  if (compact.length !== 20) return "";
  return [0, 4, 8, 12, 16].map((i) => compact.slice(i, i + 4)).join("-");
}

export function randomToken(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Opaque, tamper-evident enrollment blob. Carries the already-hashed material
 * between `enroll` and `enroll_confirm` so no partially-enrolled row exists and
 * no raw secret is ever persisted or re-displayed. Never contains the raw key.
 */
export interface EnrollmentPayload {
  user_id: string;
  birthdate_hash: string;
  questions: { id: string; answer_hash: string }[];
  recovery_key_hash: string;
  tail_hash: string;
  exp: number;
}

function b64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function unb64url(s: string): string {
  return atob(s.replace(/-/g, "+").replace(/_/g, "/"));
}

export async function sealEnrollment(p: EnrollmentPayload): Promise<string> {
  const body = b64url(JSON.stringify(p));
  const mac = await keyedHash("enrollment_blob", p.user_id, body);
  return `${body}.${mac}`;
}

export async function openEnrollment(token: string): Promise<EnrollmentPayload | null> {
  const [body, mac] = (token ?? "").split(".");
  if (!body || !mac) return null;
  let parsed: EnrollmentPayload;
  try {
    parsed = JSON.parse(unb64url(body)) as EnrollmentPayload;
  } catch {
    return null;
  }
  if (!parsed?.user_id) return null;
  const expected = await keyedHash("enrollment_blob", parsed.user_id, body);
  if (!safeEqual(expected, mac)) return null;
  if (!parsed.exp || parsed.exp < Date.now()) return null;
  return parsed;
}