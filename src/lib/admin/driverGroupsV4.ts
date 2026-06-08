import { supabase } from "@/integrations/supabase/client";

export type MilestoneJob = {
  id: string;
  referral_id: string | null;
  driver_user_id: string | null;
  ride_id: string | null;
  event_type: "driver_approved" | "ride_completed" | "manual_refresh" | "seven_day_check";
  status: "pending" | "processing" | "processed" | "failed";
  attempts: number;
  last_error: string | null;
  created_at: string;
  processed_at: string | null;
};

export type FieldCheckin = {
  id: string;
  group_id: string;
  leader_user_id: string | null;
  driver_user_id: string | null;
  zone_id: string | null;
  checkin_type: "field_visit" | "recruitment_visit" | "driver_meeting" | "market_station" | "issue_report" | "training";
  lat: number | null;
  lng: number | null;
  accuracy_m: number | null;
  notes: string | null;
  photo_url: string | null;
  created_by: string;
  created_at: string;
  metadata: Record<string, unknown>;
};

export type RiskReview = {
  id: string;
  entity_type: "referral" | "commission" | "payout_statement" | "group";
  entity_id: string;
  status: string;
  reason: string | null;
  reviewed_by: string | null;
  reviewed_at: string;
  metadata: Record<string, unknown>;
};

export async function listMilestoneJobs(status?: string): Promise<MilestoneJob[]> {
  let q = supabase.from("driver_referral_milestone_jobs").select("*").order("created_at", { ascending: false }).limit(200);
  if (status) q = q.eq("status", status);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as unknown as MilestoneJob[];
}

export async function processMilestoneJobs(limit = 50) {
  const { data, error } = await supabase.rpc("process_driver_referral_milestone_jobs", { p_limit: limit });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return row as { processed: number; failed: number; eligible: number } | null;
}

export async function enqueueMilestoneRefresh(p_driver: string, p_event: string = "manual_refresh") {
  const { data, error } = await supabase.rpc("admin_enqueue_milestone_refresh", { p_driver, p_event });
  if (error) throw error;
  return data as string;
}

export async function adminListCheckins(p_group?: string | null) {
  const { data, error } = await supabase.rpc("admin_list_field_checkins", {
    p_group: p_group ?? null, p_limit: 200,
  });
  if (error) throw error;
  return (data ?? []) as unknown as FieldCheckin[];
}

export async function listRiskReviews(entityType?: string, entityId?: string): Promise<RiskReview[]> {
  let q = supabase.from("driver_group_risk_reviews").select("*").order("reviewed_at", { ascending: false }).limit(200);
  if (entityType) q = q.eq("entity_type", entityType);
  if (entityId) q = q.eq("entity_id", entityId);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as unknown as RiskReview[];
}