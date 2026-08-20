/**
 * Node 4 — Marché R12: operations + exceptions client bindings.
 *
 * HARD RULE: the client never derives allowed actions, never rewrites history
 * and never touches money. Every field below is returned verbatim by
 * role-gated SECURITY DEFINER RPCs. The client only renders and dispatches
 * server-authorised commands with an explicit idempotency request id.
 */
import { supabase } from "@/integrations/supabase/client";

type Rpc = {
  rpc: (n: string, a?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
};
const db = supabase as unknown as Rpc;

export type MarcheOpsStatus = "open" | "in_review" | "resolved" | "dismissed";

export type MarcheOpsCaseType =
  | "merchant_suspension"
  | "catalog_violation"
  | "price_anomaly"
  | "fraud"
  | "procurement_anomaly"
  | "customer_dispute"
  | "shopper_dispute"
  | "rating_abuse"
  | "stock_accuracy"
  | "merchant_reliability";

export type MarcheOpsAction =
  | "add_note"
  | "assign"
  | "request_evidence"
  | "escalate"
  | "start_review"
  | "suspend_merchant"
  | "restore_merchant"
  | "quarantine_listing"
  | "restore_listing"
  | "restrict_user"
  | "unrestrict_user"
  | "moderate_rating"
  | "restore_rating"
  | "record_finance_resolution"
  | "resolve"
  | "dismiss"
  | "reopen";

export interface MarcheOpsQueueItem {
  case_id: string;
  case_type: MarcheOpsCaseType;
  severity: string;
  status: MarcheOpsStatus;
  source: string;
  reason_code: string;
  opened_at: string;
  assigned_to: string | null;
  age_hours: number;
  store_id: string | null;
  store_name: string | null;
  listing_id: string | null;
  order_id: string | null;
  mission_id: string | null;
}

export interface MarcheOpsQueue {
  counts: Partial<Record<MarcheOpsStatus, number>>;
  items: MarcheOpsQueueItem[];
  actor_role: string;
}

export interface MarcheOpsTimelineEvent {
  id: string;
  action: string;
  actor_role: string;
  reason_code: string | null;
  note: string | null;
  before_state: Record<string, unknown> | null;
  after_state: Record<string, unknown> | null;
  finance_ref: Record<string, unknown> | null;
  created_at: string;
}

export interface MarcheOpsControl {
  id: string;
  control_kind: string;
  reason_code: string | null;
  applied_at: string;
  lifted_at: string | null;
  active: boolean;
}

export interface MarcheOpsCaseDetail {
  case_id: string;
  case_type: MarcheOpsCaseType;
  severity: string;
  status: MarcheOpsStatus;
  source: string;
  detector_key: string | null;
  reason_code: string;
  note: string;
  evidence: Record<string, unknown>;
  assigned_to: string | null;
  opened_by: string | null;
  opened_at: string;
  resolution_code: string | null;
  resolved_at: string | null;
  resolved_by: string | null;
  subjects: {
    store: { id: string; name: string | null; slug: string | null; status: string | null; onboarding_status: string | null; ops_suspended: boolean } | null;
    listing: { id: string; title: string | null; status: string | null; visibility: string | null; is_orderable: boolean; refusal_reason: string | null; price_gnf: number | null; quantity_available: number | null; ops_quarantined: boolean } | null;
    order: { id: string; status: string; fulfillment_state: string; merchandise_subtotal_gnf: number | null; merchant_payable_gnf: number | null; created_at: string } | null;
    mission: { id: string; state: string; verified_spend_gnf: number | null; created_at: string } | null;
    reputation_event: { id: string; subject_kind: string; overall_score: number | null; created_at: string; moderated: boolean } | null;
    customer_user_id: string | null;
    shopper_user_id: string | null;
  };
  controls: MarcheOpsControl[];
  timeline: MarcheOpsTimelineEvent[];
  actor_role: string;
  allowed_actions: MarcheOpsAction[];
}

const ERROR_FR: Record<string, string> = {
  NOT_AUTHORIZED: "Vous n'avez pas les droits pour cette opération.",
  CASE_NOT_FOUND: "Dossier introuvable.",
  UNKNOWN_STATUS: "Statut inconnu.",
  UNKNOWN_CASE_TYPE: "Type de dossier inconnu.",
  ACTION_NOT_ALLOWED: "Cette action n'est pas autorisée sur ce dossier.",
  REQUEST_ID_REQUIRED: "Identifiant de requête manquant.",
  FINANCE_ROLE_REQUIRED: "Une résolution financière requiert un rôle Finance.",
  REASON_CODE_REQUIRED: "Un motif est obligatoire.",
  SUBJECT_REQUIRED: "Ce dossier n'a pas de sujet exploitable.",
};

export function translateOpsError(message: string): string {
  for (const key of Object.keys(ERROR_FR)) {
    if (message.includes(key)) return ERROR_FR[key];
  }
  return message;
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(translateOpsError(error.message));
  return data as T;
}

export function fetchMarcheOpsQueue(args?: {
  status?: MarcheOpsStatus | null;
  type?: MarcheOpsCaseType | null;
  search?: string | null;
  limit?: number;
}) {
  return call<MarcheOpsQueue>("marche_ops_queue", {
    p_status: args?.status ?? null,
    p_type: args?.type ?? null,
    p_search: args?.search ?? null,
    p_limit: args?.limit ?? 50,
  });
}

export function fetchMarcheOpsCase(caseId: string) {
  return call<MarcheOpsCaseDetail>("marche_ops_case_detail", { p_case_id: caseId });
}

export function openMarcheOpsCase(payload: Record<string, unknown>) {
  return call<{ case_id: string }>("marche_ops_case_open", { p_payload: payload });
}

export function runMarcheOpsCommand(args: {
  caseId: string;
  action: MarcheOpsAction;
  requestId: string;
  reasonCode?: string | null;
  note?: string | null;
  params?: Record<string, unknown>;
}) {
  return call<Record<string, unknown>>("marche_ops_command", {
    p_case_id: args.caseId,
    p_action: args.action,
    p_request_id: args.requestId,
    p_reason_code: args.reasonCode ?? null,
    p_note: args.note ?? null,
    p_params: args.params ?? {},
  });
}

export const OPS_CASE_TYPE_LABEL: Record<MarcheOpsCaseType, string> = {
  merchant_suspension: "Suspension marchand",
  catalog_violation: "Violation catalogue",
  price_anomaly: "Anomalie de prix",
  fraud: "Fraude",
  procurement_anomaly: "Anomalie d'approvisionnement",
  customer_dispute: "Litige client",
  shopper_dispute: "Litige acheteur-livreur",
  rating_abuse: "Abus d'évaluation",
  stock_accuracy: "Fiabilité du stock",
  merchant_reliability: "Fiabilité marchand",
};

export const OPS_STATUS_LABEL: Record<MarcheOpsStatus, string> = {
  open: "Ouverts",
  in_review: "En cours",
  resolved: "Résolus",
  dismissed: "Classés",
};

export const OPS_ACTION_LABEL: Record<MarcheOpsAction, string> = {
  add_note: "Ajouter une note",
  assign: "M'assigner",
  request_evidence: "Demander une preuve",
  escalate: "Escalader",
  start_review: "Prendre en charge",
  suspend_merchant: "Suspendre la boutique",
  restore_merchant: "Rétablir la boutique",
  quarantine_listing: "Mettre l'annonce en quarantaine",
  restore_listing: "Rétablir l'annonce",
  restrict_user: "Restreindre l'utilisateur",
  unrestrict_user: "Lever la restriction",
  moderate_rating: "Modérer l'évaluation",
  restore_rating: "Rétablir l'évaluation",
  record_finance_resolution: "Enregistrer la résolution financière",
  resolve: "Résoudre",
  dismiss: "Classer sans suite",
  reopen: "Rouvrir",
};

export const OPS_STATUS_ORDER: MarcheOpsStatus[] = ["open", "in_review", "resolved", "dismissed"];
