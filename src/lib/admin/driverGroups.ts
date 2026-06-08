import { supabase } from "@/integrations/supabase/client";

export type DriverGroup = {
  id: string;
  name: string;
  description: string | null;
  leader_user_id: string | null;
  leader_name: string | null;
  leader_phone: string | null;
  status: "active" | "suspended" | "archived";
  commission_percent: number;
  signup_bonus_gnf: number;
  assigned_zones: string[];
  referral_code: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

export type DriverGroupMembership = {
  id: string;
  group_id: string;
  driver_user_id: string;
  status: "active" | "removed" | "pending";
  assigned_zone: string | null;
  joined_at: string;
  notes: string | null;
};

export type DriverGroupCommission = {
  id: string;
  group_id: string;
  driver_user_id: string;
  leader_user_id: string | null;
  source_type: "ride_earning" | "signup_bonus" | "adjustment";
  source_id: string | null;
  gross_driver_earning_gnf: number;
  commission_percent: number;
  commission_amount_gnf: number;
  status: "pending" | "approved" | "paid" | "reversed";
  created_at: string;
  approved_at: string | null;
  paid_at: string | null;
  notes: string | null;
};

export type DriverReferral = {
  id: string;
  group_id: string | null;
  referred_driver_user_id: string;
  referrer_user_id: string | null;
  referral_code: string | null;
  status: "pending" | "approved" | "bonus_eligible" | "paid" | "rejected";
  bonus_amount_gnf: number;
  approved_at: string | null;
  paid_at: string | null;
  created_at: string;
};

export async function listDriverGroups() {
  const { data, error } = await supabase
    .from("driver_groups")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as DriverGroup[];
}

export async function listMemberships(groupId?: string) {
  let q = supabase.from("driver_group_memberships").select("*").order("joined_at", { ascending: false });
  if (groupId) q = q.eq("group_id", groupId);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as DriverGroupMembership[];
}

export async function listCommissions(groupId?: string) {
  let q = supabase.from("driver_group_commissions").select("*").order("created_at", { ascending: false }).limit(500);
  if (groupId) q = q.eq("group_id", groupId);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as DriverGroupCommission[];
}

export async function listReferrals(groupId?: string) {
  let q = supabase.from("driver_referrals").select("*").order("created_at", { ascending: false }).limit(500);
  if (groupId) q = q.eq("group_id", groupId);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as DriverReferral[];
}

export async function createDriverGroup(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc("admin_create_driver_group", { payload: payload as any });
  if (error) throw error;
  return data as string;
}

export async function updateDriverGroup(p_group: string, payload: Record<string, unknown>) {
  const { error } = await supabase.rpc("admin_update_driver_group", { p_group, payload: payload as any });
  if (error) throw error;
}

export async function assignDriverToGroup(p_group: string, p_driver: string, p_zone?: string | null, p_notes?: string | null) {
  const { data, error } = await supabase.rpc("admin_assign_driver_to_group", {
    p_group, p_driver, p_zone: p_zone ?? null, p_notes: p_notes ?? null,
  });
  if (error) throw error;
  return data as string;
}

export async function removeDriverFromGroup(p_membership: string, p_reason?: string | null) {
  const { error } = await supabase.rpc("admin_remove_driver_from_group", { p_membership, p_reason: p_reason ?? null });
  if (error) throw error;
}

export async function reviewCommission(p_commission: string, p_action: "approve" | "mark_paid" | "reverse", p_notes?: string | null) {
  if (p_action === "mark_paid") {
    const { error } = await supabase.rpc("wallet_pay_driver_commission", { p_commission_id: p_commission });
    if (error) throw error;
    return;
  }
  if (p_action === "reverse") {
    // Reverse path: if commission is already paid, debit leader via wallet RPC; otherwise admin cancellation.
    const { error } = await supabase.rpc("wallet_reverse_driver_commission", {
      p_commission_id: p_commission,
      p_reason: p_notes && p_notes.trim().length > 0 ? p_notes : "Annulation administrative",
    });
    if (!error) return;
    // Fall back to the v0 admin review (commission still pending/approved, no wallet impact).
    const msg = (error as { message?: string })?.message ?? "";
    if (!/not_paid|paid|missing/i.test(msg)) throw error;
    const { error: err2 } = await supabase.rpc("admin_review_commission", { p_commission, p_action, p_notes: p_notes ?? null });
    if (err2) throw err2;
    return;
  }
  const { error } = await supabase.rpc("admin_review_commission", { p_commission, p_action, p_notes: p_notes ?? null });
  if (error) throw error;
}

export async function markReferral(p_referral: string, p_action: "approve" | "mark_eligible" | "mark_paid" | "reject") {
  const { error } = await supabase.rpc("admin_mark_referral", { p_referral, p_action });
  if (error) throw error;
}

export function formatGnf(n: number | null | undefined) {
  const v = Number(n ?? 0);
  return v.toLocaleString("fr-FR") + " GNF";
}

export type DriverGroupStats = {
  group_id: string;
  active_drivers: number;
  rides_completed: number;
  gross_driver_earnings_gnf: number;
  commissions_pending_gnf: number;
  commissions_paid_gnf: number;
  signup_bonus_eligible_count: number;
  signup_bonus_paid_gnf: number;
};

export async function adminDriverGroupStats(opts: { groupId?: string | null; from?: Date; to?: Date } = {}) {
  const { data, error } = await supabase.rpc("admin_driver_group_stats", {
    p_group: opts.groupId ?? null,
    p_from: (opts.from ?? new Date(Date.now() - 30 * 86_400_000)).toISOString(),
    p_to: (opts.to ?? new Date()).toISOString(),
  });
  if (error) throw error;
  return (data ?? []) as unknown as DriverGroupStats[];
}