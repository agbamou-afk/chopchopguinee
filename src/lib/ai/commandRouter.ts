/**
 * CommandRouter — local, deterministic intent classifier for the smart
 * command bar. Runs instantly on every keystroke; the AI is only used as
 * a fallback for ambiguous, free-form prompts.
 *
 * Pure presentation/UX layer: no network calls, no business logic.
 */

export type CommandIntent =
  | "moto"
  | "toktok"
  | "food"
  | "market"
  | "send"
  | "scan"
  | "wallet"
  | "support"
  | "orders"
  | "navigate";

export type CommandGroup =
  | "quick"
  | "services"
  | "marche"
  | "repas"
  | "lieux"
  | "aide"
  | "compte";

export interface CommandResult {
  id: string;
  group: CommandGroup;
  groupLabel: string;
  title: string;
  subtitle?: string;
  intent: CommandIntent;
  destination?: string;
  /** Lower = better */
  score: number;
}

/** Curated locations + common spellings → canonical label. */
const LOCATIONS: Array<{ label: string; aliases: string[] }> = [
  { label: "Kaloum", aliases: ["kaloum"] },
  { label: "Kipé", aliases: ["kipe", "kipé"] },
  { label: "Bambeto", aliases: ["bambeto", "bambéto"] },
  { label: "Madina", aliases: ["madina", "madinah"] },
  { label: "Ratoma", aliases: ["ratoma"] },
  { label: "Matoto", aliases: ["matoto"] },
  { label: "Taouyah", aliases: ["taouyah", "tawya"] },
  { label: "Conakry", aliases: ["conakry", "konakry"] },
  { label: "Dixinn", aliases: ["dixinn", "dixin"] },
  { label: "Lambanyi", aliases: ["lambanyi", "lambagni"] },
  { label: "Sonfonia", aliases: ["sonfonia"] },
  { label: "Cosa", aliases: ["cosa"] },
  { label: "Nongo", aliases: ["nongo"] },
  { label: "Aéroport", aliases: ["aeroport", "aéroport", "airport", "gbessia"] },
  { label: "Matam", aliases: ["matam"] },
];

/** Synonym → intent. Matched on whole word boundaries, accent-insensitive. */
const SYNONYMS: Array<{ words: string[]; intent: CommandIntent; weight: number }> = [
  { intent: "moto", weight: 1, words: ["moto", "bike", "motorbike", "moto-taxi", "deux-roues"] },
  { intent: "toktok", weight: 1, words: ["toktok", "tok-tok", "tok tok", "triporteur", "tricycle"] },
  { intent: "moto", weight: 2, words: ["taxi", "course", "trajet", "ride"] },
  { intent: "food", weight: 1, words: ["food", "repas", "manger", "eat", "restaurant", "resto", "diner", "déjeuner", "petit dej", "à manger"] },
  { intent: "market", weight: 1, words: ["market", "marche", "marché", "shopping", "annonce", "annonces", "boutique", "produit", "produits"] },
  { intent: "send", weight: 1, words: ["send", "envoyer", "envoi", "transfer", "transfert", "virement", "argent", "money"] },
  { intent: "wallet", weight: 1, words: ["wallet", "portefeuille", "solde", "balance", "recharge", "recharger", "topup", "top-up", "top up", "credit", "crédit"] },
  { intent: "scan", weight: 1, words: ["scan", "scanner", "qr", "code"] },
  { intent: "support", weight: 1, words: ["help", "aide", "support", "probleme", "problème", "bug", "plainte", "reclamation", "réclamation", "contact"] },
  { intent: "orders", weight: 1, words: ["order", "orders", "commande", "commandes", "where is", "ou est", "où est", "suivi", "tracking", "livraison"] },
];

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Naïve fuzzy: substring with 1-char tolerance for words ≥ 5 chars. */
function loose(text: string, word: string): boolean {
  if (text.includes(word)) return true;
  if (word.length < 5) return false;
  // allow one missing/extra char
  for (let i = 0; i < word.length; i++) {
    const variant = word.slice(0, i) + word.slice(i + 1);
    if (text.includes(variant)) return true;
  }
  return false;
}

function detectLocation(text: string): { label: string; matchedAt: number } | null {
  for (const loc of LOCATIONS) {
    for (const alias of loc.aliases) {
      const i = text.indexOf(alias);
      if (i >= 0) return { label: loc.label, matchedAt: i };
    }
  }
  return null;
}

function detectIntents(text: string): Array<{ intent: CommandIntent; weight: number }> {
  const out: Array<{ intent: CommandIntent; weight: number }> = [];
  for (const syn of SYNONYMS) {
    for (const w of syn.words) {
      if (loose(text, w)) {
        out.push({ intent: syn.intent, weight: syn.weight });
        break;
      }
    }
  }
  return out;
}

const G = {
  quick: "Actions rapides",
  services: "Services",
  marche: "Marché",
  repas: "Repas",
  lieux: "Lieux",
  aide: "Aide",
  compte: "Compte",
} as const;

function svc(
  intent: CommandIntent,
  title: string,
  subtitle: string,
  group: CommandGroup,
  score: number,
  destination?: string,
): CommandResult {
  return {
    id: `${intent}:${destination ?? "_"}:${title}`,
    intent,
    title,
    subtitle,
    group,
    groupLabel: G[group],
    score,
    destination,
  };
}

/** Default suggestions shown before the user types anything. */
export function defaultSuggestions(): CommandResult[] {
  return [
    svc("moto", "Commander une Moto", "Course rapide en ville", "quick", 0),
    svc("send", "Envoyer un colis", "Livraison entre quartiers", "quick", 1),
    svc("food", "Commander un repas", "Cuisine locale et restaurants", "quick", 2),
    svc("market", "Rechercher dans Marché", "Annonces et services près de vous", "quick", 3),
    svc("wallet", "Recharger mon portefeuille", "Top-up via agent ou mobile money", "quick", 4),
  ];
}

/**
 * Classify a free-form query into ranked, grouped command results.
 * Returns an empty array when the query doesn't match anything locally —
 * caller may then fall back to the AI router.
 */
export function routeQuery(rawQuery: string): CommandResult[] {
  const q = normalize(rawQuery);
  if (!q) return defaultSuggestions();

  const loc = detectLocation(q);
  const intents = detectIntents(q);
  const seen = new Set<CommandIntent>(intents.map((i) => i.intent));

  const results: CommandResult[] = [];

  // -- Service intents (Moto / TokTok / Food / Market / Send / Scan / Wallet)
  if (seen.has("moto")) {
    results.push(
      svc(
        "moto",
        loc ? `Moto vers ${loc.label}` : "Réserver une Moto",
        loc ? "Destination prête à confirmer" : "Course rapide",
        "services",
        0,
        loc?.label,
      ),
    );
  }
  if (seen.has("toktok")) {
    results.push(
      svc(
        "toktok",
        loc ? `TokTok vers ${loc.label}` : "Réserver un TokTok",
        loc ? "Destination prête à confirmer" : "Course familiale ou colis",
        "services",
        seen.has("moto") ? 1 : 0,
        loc?.label,
      ),
    );
  }
  // "taxi" alone → propose both
  if (intents.some((i) => i.intent === "moto" && i.weight === 2) && !seen.has("toktok")) {
    results.push(svc("toktok", "Ou un TokTok", "Plus de place, même trajet", "services", 2, loc?.label));
  }

  if (seen.has("food")) {
    results.push(
      svc(
        "food",
        loc ? `Repas livrés à ${loc.label}` : "Commander un repas",
        "Restaurants et cuisine locale",
        "repas",
        0,
        loc?.label,
      ),
    );
  }

  if (seen.has("market")) {
    results.push(
      svc(
        "market",
        loc ? `Marché — annonces à ${loc.label}` : "Parcourir le Marché",
        "Produits, services et bons plans",
        "marche",
        0,
        loc?.label,
      ),
    );
  }

  if (seen.has("send")) {
    results.push(
      svc(
        "send",
        loc ? `Envoyer vers ${loc.label}` : "Envoyer de l'argent ou un colis",
        "Transferts internes en GNF",
        "compte",
        0,
        loc?.label,
      ),
    );
  }

  if (seen.has("wallet")) {
    results.push(svc("wallet", "Recharger mon portefeuille", "Agent CHOP CHOP ou mobile money", "compte", 1));
  }

  if (seen.has("scan")) {
    results.push(svc("scan", "Scanner un QR code", "Course, paiement ou marchand", "services", 3));
  }

  if (seen.has("orders")) {
    results.push(svc("orders", "Voir mes commandes", "Suivi en temps réel", "compte", 2));
  }

  if (seen.has("support")) {
    results.push(svc("support", "Centre d'aide", "FAQ et contacter l'équipe", "aide", 0));
  }

  // -- Location-only query (no service detected) → propose service options
  if (loc && intents.length === 0) {
    results.push(
      svc("moto", `Aller à ${loc.label} en Moto`, "Course rapide", "lieux", 0, loc.label),
      svc("toktok", `Aller à ${loc.label} en TokTok`, "Plus de place", "lieux", 1, loc.label),
      svc("food", `Repas à ${loc.label}`, "Restaurants du quartier", "lieux", 2, loc.label),
      svc("market", `Marché à ${loc.label}`, "Annonces locales", "lieux", 3, loc.label),
    );
  }

  // -- Always offer help as a low-priority fallback when nothing matched
  if (results.length === 0) {
    results.push(svc("support", "Demander de l'aide", "Notre équipe peut vous orienter", "aide", 99));
  }

  return results;
}

/** Group results by section, preserving group order. */
const GROUP_ORDER: CommandGroup[] = ["quick", "services", "repas", "marche", "compte", "lieux", "aide"];

export function groupResults(results: CommandResult[]): Array<{ group: CommandGroup; label: string; items: CommandResult[] }> {
  const map = new Map<CommandGroup, CommandResult[]>();
  for (const r of results) {
    const arr = map.get(r.group) ?? [];
    arr.push(r);
    map.set(r.group, arr);
  }
  for (const arr of map.values()) arr.sort((a, b) => a.score - b.score);
  return GROUP_ORDER.filter((g) => map.has(g)).map((g) => ({
    group: g,
    label: G[g],
    items: map.get(g)!,
  }));
}