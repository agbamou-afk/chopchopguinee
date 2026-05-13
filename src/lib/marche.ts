import {
  Smartphone,
  Cpu,
  Car,
  Home,
  Sofa,
  Wrench,
  Shirt,
  Sparkles,
  Briefcase,
  HardHat,
  ShoppingBasket,
  Pill,
  Baby,
  Laptop,
  Trophy,
  type LucideIcon,
} from "lucide-react";

export type MarcheCategory = {
  id: string;
  label: string;
  icon: LucideIcon;
  tint: string; // tailwind bg class
  fg: string; // tailwind text class
};

export const MARCHE_CATEGORIES: MarcheCategory[] = [
  { id: "phones", label: "Téléphones", icon: Smartphone, tint: "bg-emerald-50", fg: "text-emerald-600" },
  { id: "electronics", label: "Électronique", icon: Cpu, tint: "bg-sky-50", fg: "text-sky-600" },
  { id: "vehicles", label: "Véhicules", icon: Car, tint: "bg-amber-50", fg: "text-amber-600" },
  { id: "real_estate", label: "Immobilier", icon: Home, tint: "bg-rose-50", fg: "text-rose-600" },
  { id: "home", label: "Maison", icon: Sofa, tint: "bg-violet-50", fg: "text-violet-600" },
  { id: "tools", label: "Outils", icon: Wrench, tint: "bg-stone-100", fg: "text-stone-700" },
  { id: "fashion", label: "Mode", icon: Shirt, tint: "bg-pink-50", fg: "text-pink-600" },
  { id: "beauty", label: "Beauté", icon: Sparkles, tint: "bg-fuchsia-50", fg: "text-fuchsia-600" },
  { id: "services", label: "Services", icon: Briefcase, tint: "bg-teal-50", fg: "text-teal-600" },
  { id: "construction", label: "Construction", icon: HardHat, tint: "bg-yellow-50", fg: "text-yellow-700" },
  { id: "food_market", label: "Marché alimentaire", icon: ShoppingBasket, tint: "bg-lime-50", fg: "text-lime-700" },
  { id: "pharmacy", label: "Pharmacie", icon: Pill, tint: "bg-red-50", fg: "text-red-600" },
  { id: "baby", label: "Bébé", icon: Baby, tint: "bg-orange-50", fg: "text-orange-600" },
  { id: "computing", label: "Informatique", icon: Laptop, tint: "bg-indigo-50", fg: "text-indigo-600" },
  { id: "sports", label: "Sports", icon: Trophy, tint: "bg-cyan-50", fg: "text-cyan-600" },
];

export const categoryLabel = (id: string) =>
  MARCHE_CATEGORIES.find((c) => c.id === id)?.label ?? id;

export const formatGNF = (amount: number | null | undefined) =>
  amount == null ? "Prix à discuter" : `${new Intl.NumberFormat("fr-GN").format(amount)} GNF`;

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