/**
 * Node 4 — Marché R9: verified reputation client.
 *
 * Nothing here is authoritative. The client may only name a transaction it
 * took part in and a subject KIND; the server resolves the actual subject
 * identity from frozen transaction truth, refuses non-completed or foreign
 * transactions, and owns every published aggregate.
 */
import { supabase } from "@/integrations/supabase/client";

type Rpc = {
  rpc: (n: string, a?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
};
const db = supabase as unknown as Rpc;

export type ReputationTransactionKind = "merchant_order" | "procurement";
export type ReputationSubjectKind = "merchant_store" | "delivery_driver" | "shopper";

export interface ReputationSubjectOption {
  subject_kind: ReputationSubjectKind;
  subject_label: string;
  dimensions: string[];
  already_rated: boolean;
  my_overall_score: number | null;
}

export interface ReputationEligibility {
  eligible: boolean;
  reason: string | null;
  transaction_kind: ReputationTransactionKind;
  transaction_id: string;
  completed_at: string | null;
  subjects: ReputationSubjectOption[];
}

export interface ReputationDimensionStat {
  dimension: string;
  average: number;
  count: number;
}

export interface ReputationSummary {
  subject_kind: ReputationSubjectKind;
  subject_id: string;
  has_reputation: boolean;
  rating_count: number;
  overall_average: number | null;
  last_rated_at: string | null;
  dimensions: ReputationDimensionStat[];
}

export interface ReputationSubmitResult {
  event_id: string;
  status: "RECORDED" | "ALREADY_RATED";
  already_rated: boolean;
  subject_kind: ReputationSubjectKind;
  overall_score?: number;
}

/** Machine-readable server refusals, translated for Guinean customers. */
const REFUSALS: Record<string, string> = {
  AUTH_REQUIRED: "Connectez-vous pour noter.",
  NOT_AUTHORIZED: "Seul le client de cette transaction peut la noter.",
  TRANSACTION_NOT_FOUND: "Transaction introuvable.",
  TRANSACTION_NOT_COMPLETED: "Vous pourrez noter une fois la transaction terminée.",
  ORDER_NOT_ACTIVE: "Cette commande a été annulée.",
  UNSUPPORTED_TRANSACTION_KIND: "Ce type de transaction ne se note pas.",
  SUBJECT_NOT_AVAILABLE: "Aucun intervenant de ce type sur cette transaction.",
  SUBJECT_REQUIRED: "Intervenant manquant.",
  INVALID_SUBJECT_KIND: "Intervenant inconnu.",
  CLIENT_SUBJECT_NOT_ALLOWED: "Note invalide : l'intervenant est déterminé par CHOP CHOP.",
  CLIENT_AGGREGATE_NOT_ALLOWED: "Note invalide : les moyennes sont calculées par CHOP CHOP.",
  INVALID_SCORE: "Donnez une note entière de 1 à 5.",
  INVALID_DIMENSION: "Critère d'évaluation invalide.",
  COMMENT_TOO_LONG: "Commentaire trop long (1000 caractères maximum).",
  REPUTATION_IMMUTABLE: "Une note enregistrée ne peut plus être modifiée.",
};

export function reputationErrorFr(raw: string | null | undefined): string {
  const code = (raw ?? "").trim();
  return REFUSALS[code] ?? (code || "Erreur inattendue");
}

export const SUBJECT_LABEL_FR: Record<ReputationSubjectKind, string> = {
  merchant_store: "La boutique",
  delivery_driver: "Le livreur",
  shopper: "L'acheteur au marché",
};

export const DIMENSION_LABEL_FR: Record<string, string> = {
  quality: "Qualité des produits",
  accuracy: "Commande conforme",
  availability: "Disponibilité",
  packaging: "Emballage",
  preparation: "Rapidité de préparation",
  value: "Rapport qualité-prix",
  courtesy: "Courtoisie",
  communication: "Communication",
  timeliness: "Ponctualité",
  order_care: "Soin de la commande",
  selection_quality: "Qualité du choix",
  freshness: "Fraîcheur",
  substitution_quality: "Qualité des remplacements",
  shopping_accuracy: "Fidélité à la liste",
};

export function dimensionLabelFr(dimension: string): string {
  return DIMENSION_LABEL_FR[dimension] ?? dimension;
}

export async function getReputationEligibility(
  transactionKind: ReputationTransactionKind,
  transactionId: string,
): Promise<ReputationEligibility> {
  const { data, error } = await db.rpc("marche_reputation_eligibility", {
    p_transaction_kind: transactionKind,
    p_transaction_id: transactionId,
  });
  if (error) throw new Error(reputationErrorFr(error.message));
  return data as ReputationEligibility;
}

export async function submitReputation(input: {
  transactionKind: ReputationTransactionKind;
  transactionId: string;
  subjectKind: ReputationSubjectKind;
  overallScore: number;
  comment?: string | null;
  dimensions?: Record<string, number>;
}): Promise<ReputationSubmitResult> {
  const payload: Record<string, unknown> = {
    transaction_kind: input.transactionKind,
    transaction_id: input.transactionId,
    subject_kind: input.subjectKind,
    overall_score: input.overallScore,
  };
  const comment = (input.comment ?? "").trim();
  if (comment) payload.comment = comment;
  if (input.dimensions && Object.keys(input.dimensions).length > 0) {
    payload.dimensions = input.dimensions;
  }
  const { data, error } = await db.rpc("marche_reputation_submit", { p_payload: payload });
  if (error) throw new Error(reputationErrorFr(error.message));
  return data as ReputationSubmitResult;
}

export async function getReputationSummary(
  subjectKind: ReputationSubjectKind,
  subjectId: string,
): Promise<ReputationSummary> {
  const { data, error } = await db.rpc("marche_reputation_summary", {
    p_subject_kind: subjectKind,
    p_subject_id: subjectId,
  });
  if (error) throw new Error(reputationErrorFr(error.message));
  return data as ReputationSummary;
}

/**
 * Honest display helper: never invent a score. A subject with no verified
 * rating has no reputation yet, and the UI must say exactly that.
 */
export function reputationDisplay(summary: ReputationSummary | null): {
  hasReputation: boolean;
  scoreLabel: string;
  countLabel: string;
} {
  if (!summary || !summary.has_reputation || summary.overall_average === null) {
    return { hasReputation: false, scoreLabel: "Pas encore noté", countLabel: "" };
  }
  return {
    hasReputation: true,
    scoreLabel: summary.overall_average.toFixed(2).replace(".", ","),
    countLabel:
      summary.rating_count === 1 ? "1 note vérifiée" : `${summary.rating_count} notes vérifiées`,
  };
}