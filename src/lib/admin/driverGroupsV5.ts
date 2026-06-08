import { supabase } from "@/integrations/supabase/client";

export type GroupScorecard = {
  group_id: string;
  period_days: number;
  recruited: number;
  approved: number;
  active_drivers: number;
  rides_completed?: number;
  gross_earnings_gnf?: number;
  commissions_pending_gnf: number;
  commissions_paid_gnf: number;
  signup_bonuses_eligible: number;
  signup_bonuses_paid_gnf?: number;
  checkins_count: number;
  risk_held_count?: number;
};

export type GroupRiskRow = {
  group_id: string;
  group_name: string;
  referrals_count: number;
  risk_held: number;
  risk_review: number;
  commissions_held: number;
  last_review_at: string | null;
};

export type IncentiveSuggestion = {
  kind: string;
  target_group: string | null;
  target_zone: string | null;
  severity: "low" | "medium" | "high";
  message: string;
  signal: Record<string, unknown>;
};

export type MilestoneJobRun = {
  id: string;
  source: string;
  processed: number;
  failed: number;
  eligible: number;
  error: string | null;
  ran_at: string;
};

export async function adminGroupScorecard(p_group: string, p_days = 30): Promise<GroupScorecard | null> {
  const { data, error } = await supabase.rpc("admin_group_scorecard", { p_group, p_days });
  if (error) throw error;
  return (data as unknown as GroupScorecard) ?? null;
}

export async function leaderMyScorecard(p_days = 30): Promise<GroupScorecard | null> {
  const { data, error } = await supabase.rpc("leader_get_my_scorecard", { p_days });
  if (error) throw error;
  return (data as unknown as GroupScorecard) ?? null;
}

export async function adminGroupRiskScorecard(): Promise<GroupRiskRow[]> {
  const { data, error } = await supabase.rpc("admin_group_risk_scorecard");
  if (error) throw error;
  return (data ?? []) as unknown as GroupRiskRow[];
}

export async function adminIncentiveSuggestions(): Promise<IncentiveSuggestion[]> {
  const { data, error } = await supabase.rpc("admin_incentive_suggestions");
  if (error) throw error;
  return (data ?? []) as unknown as IncentiveSuggestion[];
}

export async function listMilestoneJobRuns(): Promise<MilestoneJobRun[]> {
  const { data, error } = await supabase
    .from("driver_referral_milestone_job_runs")
    .select("*").order("ran_at", { ascending: false }).limit(50);
  if (error) throw error;
  return (data ?? []) as unknown as MilestoneJobRun[];
}

// Upload check-in photo to private bucket. Path: {group_id}/{checkin_id|timestamp}.{ext}
export async function uploadCheckinPhoto(groupId: string, file: File, checkinId?: string): Promise<string> {
  const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "");
  const allowed = ["jpg", "jpeg", "png", "webp"];
  if (!allowed.includes(ext)) throw new Error("Format non supporté (jpg/png/webp).");
  if (file.size > 5 * 1024 * 1024) throw new Error("Photo > 5 Mo.");
  const key = `${groupId}/${checkinId ?? Date.now()}.${ext}`;
  const { error } = await supabase.storage.from("driver-group-checkins").upload(key, file, {
    cacheControl: "3600", upsert: true, contentType: file.type,
  });
  if (error) throw error;
  return key;
}

export async function signedCheckinPhotoUrl(path: string, expiresIn = 600): Promise<string | null> {
  const { data, error } = await supabase.storage.from("driver-group-checkins").createSignedUrl(path, expiresIn);
  if (error) return null;
  return data?.signedUrl ?? null;
}

// CSV row export for statement items with richer columns (period, group, leader).
export function downloadStatementCsvRich(opts: {
  filenameStub: string;
  periodStart: string;
  periodEnd: string;
  groupName: string;
  leaderLabel: string;
  rows: Array<{ item_type: string; driver_user_id: string | null; amount_gnf: number; description: string | null; source_id: string | null; created_at: string; status?: string }>;
}) {
  const header = ["period_start","period_end","group","leader","item_type","driver_user_id","amount_gnf","status","description","source_id","created_at"];
  const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
  const lines = [
    header.join(","),
    ...opts.rows.map(r => [
      opts.periodStart, opts.periodEnd, opts.groupName, opts.leaderLabel,
      r.item_type, r.driver_user_id ?? "", r.amount_gnf, r.status ?? "",
      r.description ?? "", r.source_id ?? "", r.created_at,
    ].map(esc).join(",")),
  ];
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = `${opts.filenameStub}.csv`;
  document.body.appendChild(a); a.click(); a.remove();
  URL.revokeObjectURL(url);
}