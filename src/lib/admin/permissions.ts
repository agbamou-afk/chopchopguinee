export type AdminRole = "god_admin" | "operations_admin" | "finance_admin";

export type AdminModule =
  | "dashboard"
  | "live_ops"
  | "users"
  | "drivers"
  | "merchants"
  | "vendors"
  | "wallet"
  | "pricing"
  | "orders"
  | "repas"
  | "marche"
  | "support"
  | "risk"
  | "notifications"
  | "promotions"
  | "reports"
  | "zones"
  | "flags"
  | "settings"
  | "admins"
  | "audit"
  | "analytics";

export type Capability = "view" | "edit" | "approve" | "export" | "delete";

const ALL: Capability[] = ["view", "edit", "approve", "export", "delete"];

export const PERMISSIONS: Record<AdminRole, Partial<Record<AdminModule, Capability[]>>> = {
  god_admin: {
    dashboard: ALL, live_ops: ALL, users: ALL, drivers: ALL, merchants: ALL,
    vendors: ALL, wallet: ALL, pricing: ALL, orders: ALL, repas: ALL, marche: ALL,
    support: ALL, risk: ALL, notifications: ALL, promotions: ALL, reports: ALL,
    zones: ALL, flags: ALL, settings: ALL, admins: ALL, audit: ALL, analytics: ALL,
  },
  operations_admin: {
    dashboard: ["view"],
    live_ops: ["view", "edit"],
    users: ["view", "edit"],
    drivers: ["view", "edit"],
    merchants: ["view", "edit"],
    vendors: ["view"],
    wallet: ["view"],
    pricing: ["view"],
    orders: ["view", "edit"],
    repas: ["view", "edit"],
    marche: ["view", "edit", "delete"],
    support: ["view", "edit"],
    risk: ["view", "edit"],
    notifications: ["view", "edit"],
    promotions: ["view"],
    reports: ["view"],
    audit: ["view"],
    analytics: ["view"],
  },
  finance_admin: {
    dashboard: ["view"],
    users: ["view"],
    merchants: ["view", "edit"],
    vendors: ["view", "edit", "approve"],
    wallet: ["view", "edit", "approve", "export"],
    pricing: ["view"],
    orders: ["view"],
    repas: ["view"],
    marche: ["view"],
    support: ["view"],
    risk: ["view", "edit"],
    notifications: ["view"],
    reports: ["view", "export"],
    audit: ["view"],
    analytics: ["view"],
  },
};

export function can(
  role: AdminRole | null | undefined,
  module: AdminModule,
  cap: Capability = "view",
): boolean {
  if (!role) return false;
  return PERMISSIONS[role]?.[module]?.includes(cap) ?? false;
}

/** Actions that always require super_admin approval, regardless of caller role. */
export const APPROVAL_REQUIRED_ACTIONS = new Set<string>([
  "refund.large",
  "wallet.correction",
  "wallet.reverse",
  "vendor.float.increase_above_limit",
  "driver.payout.above_limit",
  "merchant.payout.above_limit",
  "pricing.change",
  "commission.change",
  "admin.create",
  "broadcast.bulk",
]);

export function requiresApproval(action: string): boolean {
  return APPROVAL_REQUIRED_ACTIONS.has(action);
}

export const ROLE_LABELS: Record<AdminRole, string> = {
  god_admin: "GOD Admin",
  operations_admin: "Operations Admin",
  finance_admin: "Finance Admin",
};