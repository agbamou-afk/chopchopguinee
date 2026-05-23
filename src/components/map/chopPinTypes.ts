import {
  Smartphone, Cpu, Car, Home as HomeIcon, Armchair, Wrench,
  Shirt, Sparkles, Briefcase, HardHat, ShoppingBasket, Pill,
  Baby, Laptop, Trophy,
  User, UtensilsCrossed, Store, Bike,
  Package, Route, Check, Flag,
  Clock, Pause, X,
  MapPin, Navigation,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

/**
 * CHOPCHOP — Langage de Pins Unifié
 * Centralized token + glyph mapping for every pin rendered across the app.
 *
 * Universal color semantics:
 *  green  → availability / success / courier / active service
 *  blue   → client / user / information
 *  orange → food / Repas / energy / pickup attention
 *  purple → commerce / boutique / Marché
 *  red    → urgency / cancellation / alert
 *  yellow → waiting / attention / in-progress caution
 *  gray   → neutral / completed / inactive
 */

export type ChopPinCategory =
  | "telephones" | "electronics" | "vehicles" | "real_estate"
  | "home" | "tools" | "fashion" | "beauty" | "services"
  | "construction" | "food_market" | "pharmacy" | "baby"
  | "computing" | "sports";

export type ChopPinActor = "client" | "restaurant" | "boutique" | "courier";

export type ChopPinMission =
  | "pickup" | "dropoff" | "handoff" | "active_mission" | "completed";

export type ChopPinStatus = "confirmed" | "in_progress" | "waiting" | "cancelled";

export type ChopPinKind =
  | { family: "category"; key: ChopPinCategory }
  | { family: "actor"; key: ChopPinActor }
  | { family: "mission"; key: ChopPinMission }
  | { family: "status"; key: ChopPinStatus };

export type ChopPinTone =
  | "green" | "blue" | "orange" | "purple" | "red" | "yellow" | "gray";

export const TONE_HSL: Record<ChopPinTone, string> = {
  green:  "hsl(146 60% 32%)",
  blue:   "hsl(212 78% 48%)",
  orange: "hsl(22 88% 52%)",
  purple: "hsl(265 50% 46%)",
  red:    "hsl(0 72% 50%)",
  yellow: "hsl(42 92% 52%)",
  gray:   "hsl(220 8% 55%)",
};

const CATEGORY_TONE: Record<ChopPinCategory, ChopPinTone> = {
  telephones: "green", electronics: "green", vehicles: "green",
  real_estate: "green", home: "green", tools: "green", fashion: "green",
  beauty: "green", services: "green", construction: "green",
  food_market: "green", pharmacy: "green", baby: "green",
  computing: "green", sports: "green",
};

const ACTOR_TONE: Record<ChopPinActor, ChopPinTone> = {
  client: "blue", restaurant: "orange", boutique: "purple", courier: "green",
};

const MISSION_TONE: Record<ChopPinMission, ChopPinTone> = {
  pickup: "blue", dropoff: "green", handoff: "orange",
  active_mission: "red", completed: "gray",
};

const STATUS_TONE: Record<ChopPinStatus, ChopPinTone> = {
  confirmed: "green", in_progress: "yellow", waiting: "blue", cancelled: "red",
};

const CATEGORY_ICON: Record<ChopPinCategory, LucideIcon> = {
  telephones: Smartphone, electronics: Cpu, vehicles: Car,
  real_estate: HomeIcon, home: Armchair, tools: Wrench, fashion: Shirt,
  beauty: Sparkles, services: Briefcase, construction: HardHat,
  food_market: ShoppingBasket, pharmacy: Pill, baby: Baby,
  computing: Laptop, sports: Trophy,
};

const ACTOR_ICON: Record<ChopPinActor, LucideIcon> = {
  client: User, restaurant: UtensilsCrossed, boutique: Store, courier: Bike,
};

const MISSION_ICON: Record<ChopPinMission, LucideIcon> = {
  pickup: MapPin, dropoff: Flag, handoff: Package,
  active_mission: Route, completed: Check,
};

const STATUS_ICON: Record<ChopPinStatus, LucideIcon> = {
  confirmed: Check, in_progress: Navigation, waiting: Clock, cancelled: X,
};

export function pinTone(kind: ChopPinKind): ChopPinTone {
  switch (kind.family) {
    case "category": return CATEGORY_TONE[kind.key];
    case "actor":    return ACTOR_TONE[kind.key];
    case "mission":  return MISSION_TONE[kind.key];
    case "status":   return STATUS_TONE[kind.key];
  }
}

export function pinIcon(kind: ChopPinKind): LucideIcon {
  switch (kind.family) {
    case "category": return CATEGORY_ICON[kind.key];
    case "actor":    return ACTOR_ICON[kind.key];
    case "mission":  return MISSION_ICON[kind.key];
    case "status":   return STATUS_ICON[kind.key];
  }
}

/** Fallback glyph for unmapped/legacy usage. */
export const FallbackPinIcon: LucideIcon = MapPin;

/** Map legacy MapMarker variant strings → ChopPinKind for backwards compat. */
export function kindFromLegacyVariant(
  variant: string,
  state?: "online" | "offline" | "busy" | "unavailable",
): ChopPinKind {
  if (state === "offline" || state === "unavailable") {
    return { family: "mission", key: "completed" };
  }
  switch (variant) {
    case "pickup":              return { family: "mission", key: "pickup" };
    case "dropoff":             return { family: "mission", key: "dropoff" };
    case "moto":
    case "toktok":
    case "livraison":           return { family: "actor", key: "courier" };
    case "food":                return { family: "actor", key: "restaurant" };
    case "marche":
    case "marketplace_pickup": return { family: "actor", key: "boutique" };
    case "user_pickup":         return { family: "actor", key: "client" };
    case "wallet":              return { family: "category", key: "services" };
    default:                    return { family: "mission", key: "active_mission" };
  }
}
