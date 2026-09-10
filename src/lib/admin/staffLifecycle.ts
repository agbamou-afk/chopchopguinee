import { supabase } from "@/integrations/supabase/client";

/**
 * G3 — staff account lifecycle client seam.
 *
 * The browser is a MIRROR only. Every rule below (four-eyes, quorum, canonical
 * class, readiness, idempotency) is enforced by the database and the
 * `admin-staff-lifecycle` edge function; nothing here can grant authority.
 */

export const STAFF_CAPABILITY = "governance.staff.manage";

/** The only two classes G3 may ever provision. God Admin is not creatable here. */
export const STAFF_CLASSES = ["operations_admin", "finance_admin"] as const;
export type StaffClass = (typeof STAFF_CLASSES)[number];

export const STAFF_CLASS_LABELS: Record<StaffClass, string> = {
  operations_admin: "Operations Admin",
  finance_admin: "Finance Admin",
};

export type LifecycleAction = "CREATE" | "DEACTIVATE" | "REACTIVATE" | "ROLE_CHANGE" | "ACCESS_RESET";

export const QUORUM_UNAVAILABLE_MESSAGE =
  "Quorum d’approbation indisponible — un deuxième God Admin actif est requis.";

/** Canonical outcome contract of the lifecycle edge function. */
export const LIFECYCLE_MESSAGES: Record<string, string> = {
  CREATED: "Compte staff créé.",
  ALREADY_COMPLETED: "Opération déjà effectuée — aucun doublon créé.",
  RESUME: "Opération reprise là où elle s’était arrêtée.",
  DEACTIVATED: "Compte staff désactivé.",
  REACTIVATE: "Compte staff réactivé.",
  ROLE_CHANGE: "Classe du compte modifiée.",
  ACCESS_RESET: "Accès réinitialisé.",
  ACCOUNT_ALREADY_EXISTS:
    "Un compte existe déjà avec cet email. Aucune autorité staff ne lui a été accordée.",
  PENDING_APPROVAL:
    "Double validation requise : un second God Admin doit approuver cette opération.",
  APPROVER_QUORUM_UNAVAILABLE: QUORUM_UNAVAILABLE_MESSAGE,
  IDEMPOTENCY_INTENT_MISMATCH:
    "Cette clé d’opération a déjà été utilisée avec des informations différentes.",
  TARGET_CONFLICT: "Opération impossible sur ce compte.",
  FORBIDDEN: "Accès refusé : opération réservée au God Admin.",
  FAILED_RETRYABLE: "Échec temporaire. Relancez la même opération.",
  FAILED_FINAL: "Opération définitivement échouée. Créez une nouvelle demande.",
};

export const READINESS_LABELS: Record<string, string> = {
  ready: "Actif / prêt",
  temp_password_required: "Mot de passe temporaire à changer",
  inactive: "Suspendu / inactif",
  not_staff: "Non staff",
};

export interface StaffRosterRow {
  user_id: string;
  full_name: string | null;
  phone: string | null;
  canonical_role: string | null;
  legacy_role: string | null;
  status: string;
  readiness: string;
  must_change_password: boolean;
  changed_password_at: string | null;
  created_at: string;
  last_action: string | null;
  last_action_at: string | null;
  last_outcome: string | null;
}

export interface QuorumStatus {
  capability: string;
  mode: string | null;
  approval_required: boolean;
  other_active_god_admins: number;
  quorum_available: boolean;
}

export interface LifecycleResponse {
  ok: boolean;
  result: string;
  message?: string;
  user_id?: string | null;
  temporary_password?: string | null;
  admin_role?: string | null;
  username?: string;
  email?: string;
  sessions_revoked?: boolean;
}

/** Server-derived material — must byte-match the DB intent hash inputs. */
export function lifecycleMaterial(params: {
  action: LifecycleAction;
  role: StaffClass | null;
  mustChange?: boolean;
}) {
  return {
    action: params.action,
    admin_role: params.role,
    must_change_password: params.mustChange !== false,
  };
}

export function lifecycleTargetType(action: LifecycleAction) {
  return action === "CREATE" ? "staff_email" : "staff_user";
}

/** Human message for an outcome code, never a raw transport error. */
export function lifecycleMessage(result: string, serverMessage?: string | null): string {
  return serverMessage || LIFECYCLE_MESSAGES[result] || LIFECYCLE_MESSAGES.FAILED_RETRYABLE;
}

export async function callStaffLifecycle(body: Record<string, unknown>): Promise<LifecycleResponse> {
  const { data, error } = await supabase.functions.invoke("admin-staff-lifecycle", { body });
  if (data && typeof data === "object" && "result" in (data as object)) {
    return data as LifecycleResponse;
  }
  // Transport-level failure only. Never surface the raw "non-2xx" copy as-is.
  return {
    ok: false,
    result: "FAILED_RETRYABLE",
    message: error?.message
      ? `Échec temporaire du service staff. Relancez la même opération.`
      : LIFECYCLE_MESSAGES.FAILED_RETRYABLE,
  };
}

export async function fetchStaffRoster(): Promise<{ rows: StaffRosterRow[]; error: string | null }> {
  const { data, error } = await (supabase.rpc as any)("admin_staff_roster");
  if (error) return { rows: [], error: error.message };
  return { rows: (data ?? []) as StaffRosterRow[], error: null };
}

export async function fetchQuorumStatus(): Promise<QuorumStatus | null> {
  const { data, error } = await (supabase.rpc as any)("admin_staff_quorum_status");
  if (error) return null;
  return data as QuorumStatus;
}

export async function fetchLifecycleHistory(limit = 50) {
  const { data, error } = await (supabase.rpc as any)("admin_staff_lifecycle_history", { _limit: limit });
  if (error) return [];
  return (data ?? []) as Array<{
    id: string; action: string; target_user_id: string | null; target_label: string | null;
    state: string; outcome: string | null; error_code: string | null; approval_id: string | null;
    target_role: string | null; previous_role: string | null; reason: string | null;
    created_at: string; completed_at: string | null;
  }>;
}

export async function fetchStaffApprovals(limit = 25) {
  const { data, error } = await (supabase.rpc as any)("admin_staff_approvals", { _limit: limit });
  if (error) return [];
  return (data ?? []) as Array<{
    id: string; status: string; target_type: string | null; target_id: string | null;
    material: Record<string, unknown> | null; requested_by: string | null; reviewed_by: string | null;
    expires_at: string | null; consumed_at: string | null; created_at: string; usable: boolean;
  }>;
}

/** Approval truth for the UI. An existing request is NEVER an executed action. */
export function approvalState(a: { status: string; consumed_at: string | null; expires_at: string | null }):
  "pending" | "ready" | "consumed" | "expired" | "rejected" {
  if (a.consumed_at) return "consumed";
  if (a.status === "rejected" || a.status === "cancelled") return "rejected";
  if (a.expires_at && new Date(a.expires_at).getTime() < Date.now()) return "expired";
  if (a.status === "approved") return "ready";
  return "pending";
}

export const APPROVAL_STATE_LABELS: Record<string, string> = {
  pending: "En attente de validation",
  ready: "Approuvée — exécutable",
  consumed: "Consommée",
  expired: "Expirée",
  rejected: "Rejetée",
};

/** Actions that are constitutionally impossible are never offered. */
export function availableActions(row: StaffRosterRow, callerId: string | null): LifecycleAction[] {
  if (row.user_id === callerId) return [];
  if (row.canonical_role === "god_admin" || row.legacy_role === "god_admin" || row.legacy_role === "super_admin") {
    return [];
  }
  if (row.status === "active") return ["ROLE_CHANGE", "ACCESS_RESET", "DEACTIVATE"];
  return ["REACTIVATE"];
}
