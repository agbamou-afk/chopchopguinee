import { supabase } from "@/integrations/supabase/client";

export type FieldPilotStatus = "planned" | "active" | "paused" | "completed" | "cancelled";
export type FieldAssignmentRole = "field_captain" | "field_agent" | "verifier";
export type FieldAssignmentStatus = "active" | "paused" | "completed" | "removed";
export type FieldVisitInterest = "cold" | "interested" | "signed_up" | "needs_follow_up" | "rejected";
export type FieldVisitStatus = "visited" | "submitted" | "duplicate_possible" | "needs_review" | "converted" | "rejected";
export type FieldReportStatus = "submitted" | "reviewed" | "needs_correction" | "approved";

export const INTEREST_LABEL: Record<FieldVisitInterest, string> = {
  cold: "Froid",
  interested: "Intéressé",
  signed_up: "Inscrit",
  needs_follow_up: "À relancer",
  rejected: "Refusé",
};

export const VISIT_STATUS_LABEL: Record<FieldVisitStatus, string> = {
  visited: "Visité",
  submitted: "Soumis",
  duplicate_possible: "Doublon possible",
  needs_review: "À revoir",
  converted: "Converti",
  rejected: "Refusé",
};

export const REPORT_STATUS_LABEL: Record<FieldReportStatus, string> = {
  submitted: "Soumis",
  reviewed: "Examiné",
  needs_correction: "À corriger",
  approved: "Approuvé",
};

const sb = supabase as any;

export async function listPilots() {
  const { data, error } = await sb.from("field_pilots").select("*").order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function upsertPilot(payload: any) {
  const { data, error } = await sb.from("field_pilots").upsert(payload).select().single();
  if (error) throw error;
  return data;
}

export async function setPilotStatus(id: string, status: FieldPilotStatus) {
  const { error } = await sb.from("field_pilots").update({ status }).eq("id", id);
  if (error) throw error;
}

export async function listAssignments(pilotId: string) {
  const { data, error } = await sb.from("field_assignments").select("*").eq("pilot_id", pilotId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function createAssignment(payload: {
  pilot_id: string; user_id: string; role: FieldAssignmentRole; assigned_zone_id?: string | null;
}) {
  const { error } = await sb.from("field_assignments").insert(payload);
  if (error) throw error;
}

export async function updateAssignmentStatus(id: string, status: FieldAssignmentStatus) {
  const { error } = await sb.from("field_assignments").update({ status }).eq("id", id);
  if (error) throw error;
}

export async function listVisits(pilotId?: string | null) {
  let q = sb.from("field_merchant_visits").select("*").order("created_at", { ascending: false }).limit(300);
  if (pilotId) q = q.eq("pilot_id", pilotId);
  const { data, error } = await q;
  if (error) throw error;
  return data ?? [];
}

export async function listReports(pilotId?: string | null) {
  let q = sb.from("field_daily_reports").select("*").order("report_date", { ascending: false }).limit(300);
  if (pilotId) q = q.eq("pilot_id", pilotId);
  const { data, error } = await q;
  if (error) throw error;
  return data ?? [];
}

export async function setReportStatus(id: string, status: FieldReportStatus, reviewerId: string) {
  const { error } = await sb.from("field_daily_reports").update({
    status, reviewed_by: reviewerId, reviewed_at: new Date().toISOString(),
  }).eq("id", id);
  if (error) throw error;
}

export async function submitDailyReport(payload: {
  pilot_id: string;
  zone_id?: string | null;
  merchants_visited_count: number;
  merchants_submitted_count: number;
  merchants_interested_count: number;
  merchants_converted_count: number;
  transport_morning_paid: boolean;
  transport_return_paid: boolean;
  notes?: string | null;
}) {
  const { data: u } = await sb.auth.getUser();
  const uid = u?.user?.id;
  if (!uid) throw new Error("auth required");
  const { error } = await sb.from("field_daily_reports").upsert(
    { ...payload, user_id: uid, report_date: new Date().toISOString().slice(0, 10) },
    { onConflict: "pilot_id,user_id,report_date" },
  );
  if (error) throw error;
}

export async function submitVisit(args: {
  pilotId: string;
  merchantName: string;
  phone?: string;
  category?: string;
  interest?: FieldVisitInterest;
  lat?: number | null;
  lng?: number | null;
  addressText?: string;
  landmark?: string;
  entrance?: string;
  pickup?: string;
  notes?: string;
  zoneId?: string | null;
}): Promise<string> {
  const { data, error } = await sb.rpc("field_submit_visit", {
    p_pilot_id: args.pilotId,
    p_merchant_name: args.merchantName,
    p_merchant_phone: args.phone ?? null,
    p_merchant_category: args.category ?? null,
    p_interest_level: args.interest ?? "cold",
    p_lat: args.lat ?? null,
    p_lng: args.lng ?? null,
    p_address_text: args.addressText ?? null,
    p_landmark_note: args.landmark ?? null,
    p_entrance_note: args.entrance ?? null,
    p_pickup_note: args.pickup ?? null,
    p_notes: args.notes ?? null,
    p_zone_id: args.zoneId ?? null,
  });
  if (error) throw error;
  return data as string;
}

export async function linkVisitToMerchantStore(visitId: string, storeId: string) {
  const { error } = await sb.from("field_merchant_visits").update({
    linked_merchant_store_id: storeId, visit_status: "converted",
  }).eq("id", visitId);
  if (error) throw error;
}

export async function listMyAssignments() {
  const { data: u } = await sb.auth.getUser();
  const uid = u?.user?.id;
  if (!uid) return [];
  const { data, error } = await sb.from("field_assignments").select("*, field_pilots(*)")
    .eq("user_id", uid).eq("status", "active");
  if (error) throw error;
  return data ?? [];
}