import { Bike, UtensilsCrossed, ShoppingBag, Package, type LucideIcon } from "lucide-react";
import type { Mission, MissionState, MissionType } from "./types";
import type { ChopPinActor, ChopPinTone } from "@/components/map/chopPinTypes";

/**
 * Per-mission-type identity + fulfillment pipeline.
 * Single source of truth for the differentiated tiles and active cards.
 *
 * Keep this presentation-only — DB state machine lives in missions.ts and
 * MISSION_NEXT_STATE in types.ts. We only customize labels, accents, proof
 * hints, and directions copy by type here.
 */

export interface MissionTypeIdentity {
  label: string;          // tile title
  subtitle: string;       // operational subtitle
  trustHint: string;      // calm trust/proof hint
  icon: LucideIcon;
  /** Accept-CTA copy on the incoming request card. */
  acceptCta: string;
  /** Pickup/dropoff actor labels for endpoint chips. */
  endpointLabels: { pickup: string; dropoff: string };
  /** Spatial: actor kinds for pickup / dropoff pins. */
  pinActors: { pickup: ChopPinActor; dropoff: ChopPinActor };
  /** Route polyline tone — keeps mission identity on the map. */
  routeTone: ChopPinTone;
  /** Tailwind classes — keep subtle, semantic tokens only. */
  accent: {
    iconBg: string;       // background of icon chip
    iconText: string;     // icon color
    border: string;       // card border tint
    chipText: string;     // label/eyebrow color
  };
}

export const MISSION_IDENTITY: Record<MissionType, MissionTypeIdentity> = {
  ride: {
    label: "Course Moto",
    subtitle: "Transport passager",
    trustHint: "Pickup client à confirmer",
    icon: Bike,
    acceptCta: "Accepter la course",
    endpointLabels: { pickup: "Client", dropoff: "Destination" },
    pinActors: { pickup: "client", dropoff: "client" },
    routeTone: "green",
    accent: {
      iconBg: "bg-accent-moto/15",
      iconText: "text-accent-moto",
      border: "border-accent-moto/30",
      chipText: "text-accent-moto",
    },
  },
  food_delivery: {
    label: "Livraison Repas",
    subtitle: "Commande repas à récupérer",
    trustHint: "Photo au restaurant + photo livraison",
    icon: UtensilsCrossed,
    acceptCta: "Accepter la livraison",
    endpointLabels: { pickup: "Restaurant", dropoff: "Client" },
    pinActors: { pickup: "restaurant", dropoff: "client" },
    routeTone: "orange",
    accent: {
      iconBg: "bg-accent-repas/15",
      iconText: "text-accent-repas",
      border: "border-accent-repas/30",
      chipText: "text-accent-repas",
    },
  },
  marketplace_delivery: {
    label: "Livraison Marché",
    subtitle: "Article vendeur à récupérer",
    trustHint: "Article vendeur à vérifier",
    icon: ShoppingBag,
    acceptCta: "Accepter la mission",
    endpointLabels: { pickup: "Boutique", dropoff: "Acheteur" },
    pinActors: { pickup: "boutique", dropoff: "client" },
    routeTone: "purple",
    accent: {
      iconBg: "bg-accent-marche/15",
      iconText: "text-accent-marche",
      border: "border-accent-marche/30",
      chipText: "text-accent-marche",
    },
  },
  package_delivery: {
    label: "Envoyer colis",
    subtitle: "Colis à transporter",
    trustHint: "Colis suivi par WONGO",
    icon: Package,
    acceptCta: "Prendre le colis",
    endpointLabels: { pickup: "Expéditeur", dropoff: "Destinataire" },
    pinActors: { pickup: "client", dropoff: "client" },
    routeTone: "gray",
    accent: {
      iconBg: "bg-accent-envoyer/15",
      iconText: "text-accent-envoyer",
      border: "border-accent-envoyer/30",
      chipText: "text-accent-envoyer",
    },
  },
};

/** Whether a photo proof is requested before this state can be confirmed. */
export type ProofRequirement = "required" | "optional" | "none";

export interface PipelineStep {
  /** The state this step represents (drives the timeline dot). */
  key: MissionState;
  /** Short label under the timeline dot. */
  short: string;
  /** Long courier-facing CTA label when this step is current. */
  cta: string;
  /** Optional photo proof prompt — drives the "Ajouter photo …" block. */
  proof?: { requirement: ProofRequirement; label: string };
}

export interface MissionPipeline {
  steps: PipelineStep[];
  /** Directions CTA label per current state. */
  directions: Partial<Record<MissionState, string>>;
  /** Customer-facing toast copy per state. */
  customer: Partial<Record<MissionState, string>>;
}

const RIDE_PIPELINE: MissionPipeline = {
  steps: [
    { key: "heading_to_pickup", short: "Vers client", cta: "Aller chercher le client" },
    { key: "arrived_pickup", short: "Au client", cta: "Je suis arrivé" },
    { key: "picked_up", short: "Client récupéré", cta: "Client récupéré" },
    { key: "heading_to_dropoff", short: "En course", cta: "Aller à destination" },
    { key: "arrived_dropoff", short: "Arrivé", cta: "Course terminée" },
  ],
  directions: {
    assigned: "Itinéraire vers le client",
    heading_to_pickup: "Itinéraire vers le client",
    picked_up: "Itinéraire vers la destination",
    heading_to_dropoff: "Itinéraire vers la destination",
  },
  customer: {
    heading_to_pickup: "Votre chauffeur arrive.",
    arrived_pickup: "Votre chauffeur est arrivé.",
    picked_up: "Course commencée.",
    heading_to_dropoff: "En route vers votre destination.",
    delivered: "Course terminée.",
    failed: "Un problème a été signalé sur votre course.",
  },
};

const REPAS_PIPELINE: MissionPipeline = {
  steps: [
    { key: "heading_to_pickup", short: "Vers resto", cta: "Aller au restaurant" },
    { key: "arrived_pickup", short: "Au resto", cta: "Je suis au restaurant",
      proof: { requirement: "required", label: "Ajouter photo pickup" } },
    { key: "picked_up", short: "Récupéré", cta: "Commande récupérée" },
    { key: "heading_to_dropoff", short: "Vers client", cta: "Aller au client" },
    { key: "arrived_dropoff", short: "Livré", cta: "Confirmer la livraison",
      proof: { requirement: "required", label: "Ajouter photo livraison" } },
  ],
  directions: {
    assigned: "Itinéraire vers le restaurant",
    heading_to_pickup: "Itinéraire vers le restaurant",
    picked_up: "Itinéraire vers le client",
    heading_to_dropoff: "Itinéraire vers le client",
  },
  customer: {
    heading_to_pickup: "Un coursier prend en charge votre commande.",
    picked_up: "Votre commande est récupérée.",
    heading_to_dropoff: "Votre repas est en route.",
    arrived_dropoff: "Le coursier est arrivé.",
    delivered: "Commande livrée. Bon appétit !",
    failed: "Un problème a été signalé sur votre livraison.",
  },
};

const MARCHE_PIPELINE: MissionPipeline = {
  steps: [
    { key: "heading_to_pickup", short: "Vers vendeur", cta: "Aller chez le vendeur" },
    { key: "arrived_pickup", short: "Au vendeur", cta: "Vérifier l’article",
      proof: { requirement: "optional", label: "Photo de l’article" } },
    { key: "picked_up", short: "Récupéré", cta: "Article récupéré" },
    { key: "heading_to_dropoff", short: "Vers acheteur", cta: "Aller chez l’acheteur" },
    { key: "arrived_dropoff", short: "Livré", cta: "Livraison confirmée" },
  ],
  directions: {
    assigned: "Itinéraire vers le vendeur",
    heading_to_pickup: "Itinéraire vers le vendeur",
    picked_up: "Itinéraire vers l’acheteur",
    heading_to_dropoff: "Itinéraire vers l’acheteur",
  },
  customer: {
    heading_to_pickup: "Un coursier prend en charge votre article.",
    picked_up: "Votre article a été récupéré.",
    heading_to_dropoff: "Votre livraison Marché est en route.",
    arrived_dropoff: "Le coursier est arrivé.",
    delivered: "Livraison Marché reçue.",
    failed: "Un problème a été signalé sur votre livraison.",
  },
};

const PACKAGE_PIPELINE: MissionPipeline = {
  steps: [
    { key: "heading_to_pickup", short: "Vers départ", cta: "Aller au point de départ" },
    { key: "arrived_pickup", short: "Au départ", cta: "Confirmer le colis",
      proof: { requirement: "optional", label: "Photo du colis" } },
    { key: "picked_up", short: "Colis pris", cta: "Colis récupéré" },
    { key: "heading_to_dropoff", short: "Vers destinataire", cta: "Aller au destinataire" },
    { key: "arrived_dropoff", short: "Remis", cta: "Remise confirmée" },
  ],
  directions: {
    assigned: "Itinéraire vers l’expéditeur",
    heading_to_pickup: "Itinéraire vers l’expéditeur",
    picked_up: "Itinéraire vers le destinataire",
    heading_to_dropoff: "Itinéraire vers le destinataire",
  },
  customer: {
    heading_to_pickup: "Un coursier prend en charge votre colis.",
    picked_up: "Votre colis a été récupéré.",
    heading_to_dropoff: "Votre colis est en route.",
    arrived_dropoff: "Le coursier est arrivé.",
    delivered: "Colis livré.",
    failed: "Un problème a été signalé sur votre colis.",
  },
};

export const MISSION_PIPELINES: Record<MissionType, MissionPipeline> = {
  ride: RIDE_PIPELINE,
  food_delivery: REPAS_PIPELINE,
  marketplace_delivery: MARCHE_PIPELINE,
  package_delivery: PACKAGE_PIPELINE,
};

/** Resolve the step descriptor for a mission's current state. */
export function currentStep(mission: Pick<Mission, "type" | "state">): PipelineStep | null {
  const pipe = MISSION_PIPELINES[mission.type];
  const idx = pipe.steps.findIndex((s) => s.key === mission.state);
  if (idx >= 0) return pipe.steps[idx];
  // `assigned` collapses onto the first step's CTA.
  if (mission.state === "assigned") return pipe.steps[0];
  return null;
}

export function stepIndex(mission: Pick<Mission, "type" | "state">): number {
  const pipe = MISSION_PIPELINES[mission.type];
  if (mission.state === "assigned") return 0;
  if (mission.state === "delivered") return pipe.steps.length - 1;
  if (mission.state === "failed") return -1;
  return pipe.steps.findIndex((s) => s.key === mission.state);
}

export function directionsLabel(mission: Pick<Mission, "type" | "state">): string {
  return MISSION_PIPELINES[mission.type].directions[mission.state] ?? "Ouvrir l’itinéraire";
}

export function customerMessage(mission: Pick<Mission, "type" | "state">): string | null {
  return MISSION_PIPELINES[mission.type].customer[mission.state] ?? null;
}