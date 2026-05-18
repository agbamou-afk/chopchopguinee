import phonesIcon from "@/assets/icons/marche/phones.png";
import electronicsIcon from "@/assets/icons/marche/electronics.png";
import vehiclesIcon from "@/assets/icons/marche/vehicles.png";
import realEstateIcon from "@/assets/icons/marche/real_estate.png";
import homeIcon from "@/assets/icons/marche/home.png";
import toolsIcon from "@/assets/icons/marche/tools.png";
import fashionIcon from "@/assets/icons/marche/fashion.png";
import beautyIcon from "@/assets/icons/marche/beauty.png";
import servicesIcon from "@/assets/icons/marche/services.png";
import constructionIcon from "@/assets/icons/marche/construction.png";
import foodMarketIcon from "@/assets/icons/marche/food_market.png";
import pharmacyIcon from "@/assets/icons/marche/pharmacy.png";
import babyIcon from "@/assets/icons/marche/baby.png";
import computingIcon from "@/assets/icons/marche/computing.png";
import sportsIcon from "@/assets/icons/marche/sports.png";

export type MarcheCategory = {
  id: string;
  label: string;
  icon: string; // PNG asset (Kinetic Utility icon family)
  tint: string; // tailwind bg class (kept for chip backdrops)
  fg: string; // legacy tailwind text class (unused for PNG icons)
};

export const MARCHE_CATEGORIES: MarcheCategory[] = [
  { id: "phones", label: "Téléphones", icon: phonesIcon, tint: "bg-muted", fg: "" },
  { id: "electronics", label: "Électronique", icon: electronicsIcon, tint: "bg-muted", fg: "" },
  { id: "vehicles", label: "Véhicules", icon: vehiclesIcon, tint: "bg-muted", fg: "" },
  { id: "real_estate", label: "Immobilier", icon: realEstateIcon, tint: "bg-muted", fg: "" },
  { id: "home", label: "Maison", icon: homeIcon, tint: "bg-muted", fg: "" },
  { id: "tools", label: "Outils", icon: toolsIcon, tint: "bg-muted", fg: "" },
  { id: "fashion", label: "Mode", icon: fashionIcon, tint: "bg-muted", fg: "" },
  { id: "beauty", label: "Beauté", icon: beautyIcon, tint: "bg-muted", fg: "" },
  { id: "services", label: "Services", icon: servicesIcon, tint: "bg-muted", fg: "" },
  { id: "construction", label: "Construction", icon: constructionIcon, tint: "bg-muted", fg: "" },
  { id: "food_market", label: "Marché alimentaire", icon: foodMarketIcon, tint: "bg-muted", fg: "" },
  { id: "pharmacy", label: "Pharmacie", icon: pharmacyIcon, tint: "bg-muted", fg: "" },
  { id: "baby", label: "Bébé", icon: babyIcon, tint: "bg-muted", fg: "" },
  { id: "computing", label: "Informatique", icon: computingIcon, tint: "bg-muted", fg: "" },
  { id: "sports", label: "Sports", icon: sportsIcon, tint: "bg-muted", fg: "" },
];

export const categoryLabel = (id: string) =>
  MARCHE_CATEGORIES.find((c) => c.id === id)?.label ?? id;

import { formatGNF as fmtGNF } from "@/lib/format";

export const formatGNF = (amount: number | null | undefined) =>
  amount == null ? "Prix à discuter" : fmtGNF(amount);

export const timeAgo = (iso: string) => {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1) return "À l'instant";
  if (m < 60) return `Il y a ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `Il y a ${h} h`;
  const d = Math.floor(h / 24);
  if (d < 30) return `Il y a ${d} j`;
  const mo = Math.floor(d / 30);
  return `Il y a ${mo} mois`;
};

export const REPORT_REASONS = [
  { id: "scam", label: "Arnaque" },
  { id: "fake", label: "Fausse annonce" },
  { id: "prohibited", label: "Article interdit" },
  { id: "spam", label: "Spam" },
  { id: "harassment", label: "Harcèlement" },
  { id: "other", label: "Autre" },
];

export const QUICK_REPLIES = [
  "Toujours disponible ?",
  "Dernier prix ?",
  "Livraison possible ?",
  "Où êtes-vous situé ?",
];

export type SellerKind = "merchant" | "community" | "service";
export const sellerBadgeLabel = (k: SellerKind) =>
  k === "merchant" ? "Marchand vérifié" : k === "service" ? "Prestataire" : "Vendeur communauté";

// Guided description prompts — encourage richer listings without harsh min-char gates.
export const DESCRIPTION_PROMPTS = [
  "État du produit ?",
  "Marque ?",
  "Taille ?",
  "Fonctionnalités ?",
  "Livraison disponible ?",
  "Utilisé ou neuf ?",
];

export const CONDITIONS = [
  { id: "new", label: "Neuf" },
  { id: "like_new", label: "Comme neuf" },
  { id: "used", label: "Utilisé" },
] as const;

export type ConditionId = (typeof CONDITIONS)[number]["id"];

export const DISTRICTS = [
  "Kaloum", "Dixinn", "Matam", "Matoto", "Ratoma",
  "Kipé", "Kagbelen", "Lambanyi", "Coyah",
];

// Lightweight slug helper for store URLs.
export const slugify = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);

// Empty-state copy registry (Phase 7).
export const MARCHE_EMPTY_COPY = {
  listings: {
    title: "Aucune annonce disponible pour le moment.",
    hint: "Revenez plus tard ou publiez la première annonce de votre quartier.",
  },
  stores: {
    title: "Aucune boutique trouvée.",
    hint: "Essayez un autre nom ou parcourez les catégories.",
  },
  messages: {
    title: "Vos conversations apparaîtront ici.",
    hint: "Contactez un vendeur pour démarrer une discussion.",
  },
  search: {
    title: "Recherchez un produit ou une boutique.",
    hint: "Tapez un mot-clé pour voir les résultats.",
  },
} as const;

export type MarcheEmptyKey = keyof typeof MARCHE_EMPTY_COPY;

// Recent categories — local-only memory, no DB.
const RECENT_CATS_KEY = "cc_marche_recent_categories";
export function getRecentCategories(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_CATS_KEY);
    return raw ? (JSON.parse(raw) as string[]).slice(0, 4) : [];
  } catch {
    return [];
  }
}
export function pushRecentCategory(id: string) {
  try {
    const cur = getRecentCategories().filter((x) => x !== id);
    localStorage.setItem(RECENT_CATS_KEY, JSON.stringify([id, ...cur].slice(0, 4)));
  } catch {}
}