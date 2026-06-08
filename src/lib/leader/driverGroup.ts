import { supabase } from "@/integrations/supabase/client";
import type {
  DriverGroup, DriverGroupCommission, DriverReferral, DriverGroupStats,
} from "@/lib/admin/driverGroups";

export type LeaderMember = {
  id: string;
  driver_user_id: string;
  status: "active" | "removed" | "pending";
  assigned_zone: string | null;
  joined_at: string;
  driver_display: string;
  driver_phone_last4: string | null;
};

export async function leaderGetMyGroup(): Promise<DriverGroup | null> {
  const { data, error } = await supabase.rpc("leader_get_my_group");
  if (error) throw error;
  if (!data) return null;
  // RPC returns a record; supabase-js may give an object or array depending on shape.
  const row = Array.isArray(data) ? data[0] : data;
  return row && row.id ? (row as DriverGroup) : null;
}

export async function leaderListMyMembers(): Promise<LeaderMember[]> {
  const { data, error } = await supabase.rpc("leader_list_my_members");
  if (error) throw error;
  return (data ?? []) as unknown as LeaderMember[];
}

export async function leaderListMyCommissions(status?: string | null): Promise<DriverGroupCommission[]> {
  const { data, error } = await supabase.rpc("leader_list_my_commissions", { p_status: status ?? null });
  if (error) throw error;
  return (data ?? []) as unknown as DriverGroupCommission[];
}

export async function leaderListMyReferrals(status?: string | null): Promise<DriverReferral[]> {
  const { data, error } = await supabase.rpc("leader_list_my_referrals", { p_status: status ?? null });
  if (error) throw error;
  return (data ?? []) as unknown as DriverReferral[];
}

export async function leaderGetMyStats(days = 30): Promise<DriverGroupStats | null> {
  const from = new Date(Date.now() - days * 86_400_000);
  const { data, error } = await supabase.rpc("leader_get_my_stats", {
    p_from: from.toISOString(), p_to: new Date().toISOString(),
  });
  if (error) throw error;
  const rows = (data ?? []) as unknown as DriverGroupStats[];
  return rows[0] ?? null;
}