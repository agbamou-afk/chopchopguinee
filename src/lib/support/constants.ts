/**
 * CHOPCHOP Support / Issues — French-first labels and defaults.
 *
 * Kept small on purpose. This module never reads the database; it only
 * provides enumerated constants and copy used by the issue helpers,
 * the driver issue sheet, and the admin support page.
 */

export const ISSUE_TYPES = [
  "payment_pending",
  "payment_failed",
  "courier_no_show",
  "merchant_not_ready",
  "customer_unreachable",
  "wrong_address",
  "package_dispute",
  "item_not_available",
  "delivery_failed",
  "app_bug",
  "account_issue",
  "safety_concern",
  "other",
] as const;
export type IssueType = (typeof ISSUE_TYPES)[number];

export const ISSUE_STATUSES = [
  "open",
  "in_review",
  "waiting_on_user",
  "waiting_on_courier",
  "waiting_on_merchant",
  "resolved",
  "escalated",
  "cancelled",
] as const;
export type IssueStatus = (typeof ISSUE_STATUSES)[number];

export const ISSUE_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export type IssueSeverity = (typeof ISSUE_SEVERITIES)[number];

export const ISSUE_ROLES = [
  "support",
  "operations",
  "payment",
  "merchant",
  "courier",
  "admin",
] as const;
export type IssueRole = (typeof ISSUE_ROLES)[number];

export const ISSUE_TYPE_LABEL: Record<IssueType, string> = {
  payment_pending: "Paiement en attente",
  payment_failed: "Paiement échoué",
  courier_no_show: "Coursier absent",
  merchant_not_ready: "Marchand pas prêt",
  customer_unreachable: "Client injoignable",
  wrong_address: "Mauvaise adresse",
  package_dispute: "Litige colis",
  item_not_available: "Article indisponible",
  delivery_failed: "Livraison échouée",
  app_bug: "Problème technique",
  account_issue: "Problème de compte",
  safety_concern: "Sécurité",
  other: "Autre",
};

export const ISSUE_STATUS_LABEL: Record<IssueStatus, string> = {
  open: "Ouvert",
  in_review: "En examen",
  waiting_on_user: "En attente client",
  waiting_on_courier: "En attente coursier",
  waiting_on_merchant: "En attente marchand",
  resolved: "Résolu",
  escalated: "Escaladé",
  cancelled: "Annulé",
};

export const ISSUE_SEVERITY_LABEL: Record<IssueSeverity, string> = {
  low: "Faible",
  medium: "Moyen",
  high: "Élevé",
  critical: "Critique",
};

export const ISSUE_ROLE_LABEL: Record<IssueRole, string> = {
  support: "Support",
  operations: "Opérations",
  payment: "Paiement",
  merchant: "Marchand",
  courier: "Coursier",
  admin: "Admin",
};

/** Default human title when caller does not provide one. */
export function defaultIssueTitle(type: IssueType): string {
  return ISSUE_TYPE_LABEL[type];
}

/** Default assigned role per type. */
export function defaultIssueRole(type: IssueType): IssueRole {
  switch (type) {
    case "payment_pending":
    case "payment_failed":
      return "payment";
    case "merchant_not_ready":
    case "item_not_available":
      return "merchant";
    case "courier_no_show":
    case "delivery_failed":
      return "courier";
    case "safety_concern":
      return "admin";
    case "app_bug":
    case "account_issue":
      return "operations";
    default:
      return "support";
  }
}

/** Default severity per type. Critical is reserved deliberately. */
export function defaultIssueSeverity(type: IssueType): IssueSeverity {
  switch (type) {
    case "safety_concern":
      return "critical";
    case "payment_failed":
    case "delivery_failed":
    case "package_dispute":
      return "high";
    case "payment_pending":
    case "courier_no_show":
    case "merchant_not_ready":
    case "customer_unreachable":
    case "wrong_address":
      return "medium";
    default:
      return "low";
  }
}

export const ISSUE_STATUS_TONE: Record<IssueStatus, "ok" | "warn" | "alert" | "muted"> = {
  open: "warn",
  in_review: "warn",
  waiting_on_user: "muted",
  waiting_on_courier: "muted",
  waiting_on_merchant: "muted",
  resolved: "ok",
  escalated: "alert",
  cancelled: "muted",
};

export const ISSUE_SEVERITY_TONE: Record<IssueSeverity, "ok" | "warn" | "alert" | "muted"> = {
  low: "muted",
  medium: "warn",
  high: "alert",
  critical: "alert",
};