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
  | "analytics"
  | "payments"
  | "driver_groups";

export type Capability = "view" | "edit" | "approve" | "export" | "delete";

const ALL: Capability[] = ["view", "edit", "approve", "export", "delete"];

export const PERMISSIONS: Record<AdminRole, Partial<Record<AdminModule, Capability[]>>> = {
  god_admin: {
    dashboard: ALL, live_ops: ALL, users: ALL, drivers: ALL, merchants: ALL,
    vendors: ALL, wallet: ALL, pricing: ALL, orders: ALL, repas: ALL, marche: ALL,
    support: ALL, risk: ALL, notifications: ALL, promotions: ALL, reports: ALL,
    zones: ALL, flags: ALL, settings: ALL, admins: ALL, audit: ALL, analytics: ALL,
    payments: ALL, driver_groups: ALL,
  },
  operations_admin: {
    dashboard: ["view"],
    live_ops: ["view", "edit"],
    users: ["view", "edit"],
    drivers: ["view", "edit"],
    driver_groups: ["view", "edit"],
    merchants: ["view", "edit"],
    // G4: financial consoles (recharge-agent float, wallet/ledger, treasury,
    // payouts, payment intents, finance policy) are Finance/God surfaces. The
    // constitution grants Operations READ of financial *facts*, which G4 serves
    // through operational read models (ops_command_overview, order context),
    // not through mutation consoles. Least privilege: no module entry at all.
    pricing: ["view"],
    orders: ["view", "edit"],
    repas: ["view", "edit"],
    marche: ["view", "edit", "delete"],
    support: ["view", "edit"],
    risk: ["view", "edit"],
    notifications: ["view", "edit"],
    // ops.maps.manage = ALLOW: zones, places, duplicates, routing corrections.
    zones: ["view", "edit"],
    reports: ["view"],
    audit: ["view"],
    analytics: ["view"],

  },
  finance_admin: {
    dashboard: ["view"],
    users: ["view"],
    driver_groups: ["view", "approve"],
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
    payments: ["view", "edit", "approve"],
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
/**
 * G4 — constitutional binding of each frontend module to its G1 capability
 * (`docs/admin/ADMIN_CAPABILITY_CONSTITUTION.md` §8). The display layer must not
 * drift from the registry; the database capability gate remains authority.
 */
export const MODULE_CAPABILITY: Record<AdminModule, string> = {
  dashboard: "governance.capability.resolve",
  live_ops: "ops.liveops.view",
  users: "ops.users.manage",
  drivers: "ops.drivers.manage",
  driver_groups: "ops.drivers.manage",
  merchants: "ops.merchants.manage",
  vendors: "finance.payouts.manage",
  wallet: "finance.wallet.read",
  pricing: "ops.pricing.propose",
  orders: "ops.orders.manage",
  repas: "ops.orders.manage",
  marche: "ops.orders.manage",
  support: "ops.support.manage",
  risk: "ops.risk.manage",
  notifications: "ops.notifications.send",
  promotions: "governance.pricing.change",
  reports: "ops.reports.view",
  zones: "ops.maps.manage",
  flags: "governance.flags.manage",
  settings: "governance.settings.manage",
  admins: "governance.staff.manage",
  audit: "ops.audit.view_own_domain",
  analytics: "ops.analytics.view",
  payments: "finance.payouts.manage",
};

/**
 * Modules an Operations Admin must never reach, even by direct URL: financial
 * mutation consoles and governance/policy controls. Kept as an explicit list so
 * a regression in PERMISSIONS is caught by the G4 suite rather than by a user.
 */
export const OPERATIONS_FORBIDDEN_MODULES: AdminModule[] = [
  "wallet", "vendors", "payments", "promotions", "flags", "settings", "admins",
];
