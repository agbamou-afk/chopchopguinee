/**
 * Envoyer v1 — parcel / document delivery.
 *
 * The DB is the only source of truth for price, state, codes and money.
 * Everything here is a typed mirror of `public.package_deliveries` and the
 * secure RPCs. Never compute an amount client-side.
 */

export type PackageCategory = "document" | "small_parcel" | "medium_parcel";

export const PACKAGE_CATEGORY_LABEL: Record<PackageCategory, string> = {
  document: "Document / pli",
  small_parcel: "Petit colis",
  medium_parcel: "Colis moyen",
};

export const PACKAGE_CATEGORY_HINT: Record<PackageCategory, string> = {
  document: "Enveloppe, dossier, papiers administratifs",
  small_parcel: "Tient dans un sac à dos (≈ 3 kg)",
  medium_parcel: "Transportable sur une moto (≈ 8 kg)",
};

/** Items CHOPCHOP does not carry in Envoyer v1. Shown before submission. */
export const PACKAGE_PROHIBITED: string[] = [
  "Argent liquide, or, bijoux et objets de valeur",
  "Armes, munitions, produits dangereux ou inflammables",
  "Produits illégaux ou non déclarés",
  "Animaux vivants",
  "Colis trop grands ou trop lourds pour une moto",
  "Paiement à la livraison (cash à la remise)",
];

export type PackageStatus =
  | "payment_pending"
  | "dispatching"
  | "in_transit"
  | "delivered"
  | "cancelled"
  | "needs_review";

export const PACKAGE_STATUS_LABEL: Record<string, string> = {
  payment_pending: "Paiement en attente",
  dispatching: "Recherche d’un coursier",
  in_transit: "Colis en route",
  delivered: "Colis livré",
  cancelled: "Annulé",
  needs_review: "Vérification en cours",
};

export interface PackageDelivery {
  id: string;
  sender_user_id: string;
  mission_id: string | null;
  payment_intent_id: string | null;
  reference: string;
  pickup_label: string | null;
  pickup_lat: number;
  pickup_lng: number;
  destination_label: string | null;
  destination_lat: number;
  destination_lng: number;
  sender_name: string | null;
  sender_phone: string | null;
  recipient_name: string;
  recipient_phone: string;
  category: PackageCategory;
  description: string | null;
  handling_notes: string | null;
  quoted_amount_gnf: number;
  distance_meters: number | null;
  duration_seconds: number | null;
  payment_status: string;
  package_status: PackageStatus | string;
  delivered_at: string | null;
  cancelled_at: string | null;
  cancellation_fee_gnf: number;
  refund_request_id: string | null;
  support_issue_id: string | null;
  is_sandbox: boolean;
  created_at: string;
  /** Slice 6 — declared value engine (null when the engine is OFF). */
  declared_value_gnf?: number | null;
  tender?: string | null;
  value_attested_at?: string | null;
  claim_state?: string | null;
}

export interface PackageSecrets {
  package_id: string;
  pickup_code: string;
  delivery_code: string;
  pickup_verified_at: string | null;
  delivery_verified_at: string | null;
}

/* ── Slice 6 — declared value, tender and claims ─────────────────────── */

/** How the delivery fee is settled. The server freezes this at authorization. */
export type PackageTender = "cash" | "chop_pay";

export const PACKAGE_TENDER_LABEL: Record<PackageTender, string> = {
  cash: "Espèces à la remise du colis",
  chop_pay: "Chop Pay (solde CHOPCHOP)",
};

export const PACKAGE_TENDER_HINT: Record<PackageTender, string> = {
  cash: "Vous réglez la course au coursier en espèces. Aucun blocage de solde.",
  chop_pay: "Le montant est réservé sur votre solde et libéré à la livraison.",
};

/** Fallback only — the authoritative ceiling is read from the finance policy. */
export const PACKAGE_DECLARED_VALUE_FALLBACK_MAX = 500_000;

/** Frozen, versioned attestation text. Sent verbatim to the server. */
export const PACKAGE_ATTESTATION_STATEMENT =
  "Je déclare sur l’honneur que la valeur indiquée correspond à la valeur réelle du contenu de mon colis.";

export type PackageClaimState =
  | "none"
  | "open"
  | "upheld"
  | "exonerated"
  | "reconciliation_required";

export const PACKAGE_CLAIM_STATE_LABEL: Record<string, string> = {
  none: "Aucune réclamation",
  open: "Réclamation ouverte",
  upheld: "Réclamation acceptée",
  exonerated: "Coursier disculpé",
  reconciliation_required: "Réconciliation requise",
};

/** Mirror of `public.package_runtime` (read-only for participants and admins). */
export interface PackageRuntime {
  id: string;
  package_id: string;
  mission_id: string | null;
  customer_user_id: string;
  driver_user_id: string | null;
  tender: PackageTender | string;
  declared_value_gnf: number;
  delivery_fee_gnf: number;
  platform_fee_gnf: number;
  collateral_gnf: number;
  claims_exposure_gnf: number;
  customer_hold_gnf: number;
  cash_due_gnf: number;
  driver_earning_gnf: number;
  claim_paid_gnf: number;
  state: string;
  claim_state: PackageClaimState | string;
  claim_opened_at: string | null;
  resolved_at: string | null;
  picked_up_at: string | null;
  is_sandbox: boolean;
  created_at: string;
}

export type PackageClaimOutcome =
  | "customer_upheld"
  | "driver_exonerated"
  | "reconciliation_required";

export const PACKAGE_CLAIM_OUTCOME_LABEL: Record<PackageClaimOutcome, string> = {
  customer_upheld: "Réclamation acceptée (indemniser le client)",
  driver_exonerated: "Coursier disculpé (libérer la caution)",
  reconciliation_required: "Réconciliation manuelle requise",
};

export interface PackageQuote {
  quote_id: string;
  amount_gnf: number;
  currency: string;
  distance_meters: number;
  duration_seconds: number;
  category: PackageCategory;
  expires_at: string;
  authoritative: boolean;
  tariff: string;
}

export interface PackageCheckoutResult {
  idempotent: boolean;
  package_id: string;
  reference: string;
  payment_intent_id: string;
  amount_gnf: number;
  intent_state: string;
  is_sandbox?: boolean;
}

/** Mask a Guinean number for display outside the owner's own view. */
export function maskPhone(raw: string | null | undefined): string {
  if (!raw) return "—";
  const d = raw.replace(/\s+/g, "");
  if (d.length < 6) return "•••";
  return `${d.slice(0, 6)}•••${d.slice(-2)}`;
}