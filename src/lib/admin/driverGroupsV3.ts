import { supabase } from "@/integrations/supabase/client";

export type MilestoneRule =
  | "approved" | "first_ride_completed" | "five_rides_completed" | "seven_days_active";

export type CampaignStatus = "draft" | "active" | "paused" | "completed" | "cancelled";
export type ContractStatus = "draft" | "active" | "completed" | "cancelled";
export type StatementStatus = "draft" | "finalized" | "paid" | "void";
export type RiskStatus = "clear" | "review" | "held" | "rejected";

export type RecruitmentCampaign = {
  id: string;
  group_id: string;
  leader_user_id: string | null;
  name: string;
  description: string | null;
  status: CampaignStatus;
  zone_ids: string[];
  target_driver_count: number;
  target_active_driver_count: number;
  target_completed_rides: number;
  start_date: string | null;
  end_date: string | null;
  signup_bonus_gnf: number;
  milestone_rule: MilestoneRule;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

export type GroupContract = {
  id: string;
  group_id: string;
  leader_user_id: string | null;
  name: string;
  status: ContractStatus;
  period_start: string | null;
  period_end: string | null;
  target_driver_count: number;
  target_active_driver_count: number;
  target_completed_rides: number;
  target_gross_earnings_gnf: number;
  target_zone_ids: string[];
  commission_percent_override: number | null;
  bonus_pool_gnf: number | null;
  terms: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

export type PayoutStatement = {
  id: string;
  group_id: string;
  leader_user_id: string | null;
  period_start: string;
  period_end: string;
  status: StatementStatus;
  commissions_total_gnf: number;
  signup_bonuses_total_gnf: number;
  adjustments_total_gnf: number;
  total_due_gnf: number;
  generated_at: string;
  finalized_at: string | null;
  paid_at: string | null;
  notes: string | null;
};

export type PayoutStatementItem = {
  id: string;
  statement_id: string;
  item_type: "commission" | "signup_bonus" | "adjustment";
  source_id: string | null;
  driver_user_id: string | null;
  amount_gnf: number;
  description: string | null;
  created_at: string;
};

export type ZoneCoverageRow = {
  zone_id: string;
  zone_label: string;
  drivers_count: number;
  active_drivers_count: number;
  groups_count: number;
};

// Campaigns
export async function listCampaigns(): Promise<RecruitmentCampaign[]> {
  const { data, error } = await supabase
    .from("driver_recruitment_campaigns")
    .select("*").order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as RecruitmentCampaign[];
}
export async function createCampaign(payload: Record<string, unknown>): Promise<string> {
  const { data, error } = await supabase.rpc("admin_create_campaign", { payload: payload as any });
  if (error) throw error;
  return data as string;
}
export async function updateCampaign(p_campaign: string, payload: Record<string, unknown>) {
  const { error } = await supabase.rpc("admin_update_campaign", { p_campaign, payload: payload as any });
  if (error) throw error;
}
export async function attachReferralCampaign(p_referral: string, p_campaign: string, p_reason?: string | null) {
  const { error } = await supabase.rpc("admin_attach_referral_campaign", {
    p_referral, p_campaign, p_reason: p_reason ?? null,
  });
  if (error) throw error;
}

// Contracts
export async function listContracts(): Promise<GroupContract[]> {
  const { data, error } = await supabase
    .from("driver_group_contracts").select("*").order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as GroupContract[];
}
export async function createContract(payload: Record<string, unknown>): Promise<string> {
  const { data, error } = await supabase.rpc("admin_create_contract", { payload: payload as any });
  if (error) throw error;
  return data as string;
}
export async function updateContract(p_contract: string, payload: Record<string, unknown>) {
  const { error } = await supabase.rpc("admin_update_contract", { p_contract, payload: payload as any });
  if (error) throw error;
}

// Payout statements
export async function listStatements(): Promise<PayoutStatement[]> {
  const { data, error } = await supabase
    .from("driver_group_payout_statements").select("*").order("generated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as PayoutStatement[];
}
export async function listStatementItems(statementId: string): Promise<PayoutStatementItem[]> {
  const { data, error } = await supabase
    .from("driver_group_payout_statement_items").select("*")
    .eq("statement_id", statementId).order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as unknown as PayoutStatementItem[];
}
export async function generateStatement(p_group: string, p_from: string, p_to: string, p_notes?: string) {
  const { data, error } = await supabase.rpc("admin_generate_payout_statement", {
    p_group, p_from, p_to, p_notes: p_notes ?? null,
  });
  if (error) throw error;
  return data as string;
}
export async function setStatementStatus(p_statement: string, p_status: StatementStatus, p_notes?: string) {
  const { error } = await supabase.rpc("admin_set_statement_status", {
    p_statement, p_status, p_notes: p_notes ?? null,
  });
  if (error) throw error;
}

// Risk
export async function reviewReferralRisk(p_referral: string, p_action: "clear" | "hold" | "reject" | "review", p_reason?: string) {
  const { error } = await supabase.rpc("admin_review_referral_risk", {
    p_referral, p_action, p_reason: p_reason ?? null,
  });
  if (error) throw error;
}
export async function reviewCommissionRisk(p_commission: string, p_action: "clear" | "hold" | "reject" | "review", p_reason?: string) {
  const { error } = await supabase.rpc("admin_review_commission_risk", {
    p_commission, p_action, p_reason: p_reason ?? null,
  });
  if (error) throw error;
}
export async function scoreReferralRisk(p_referral: string) {
  const { data, error } = await supabase.rpc("score_driver_referral_risk", { p_referral });
  if (error) throw error;
  const rows = (data ?? []) as Array<{ score: number; status: RiskStatus; reason: string }>;
  return rows[0] ?? null;
}

// Zone coverage
export async function zoneCoverageStats(): Promise<ZoneCoverageRow[]> {
  const { data, error } = await supabase.rpc("admin_zone_coverage_stats");
  if (error) throw error;
  return (data ?? []) as unknown as ZoneCoverageRow[];
}

// Milestones
export async function refreshMilestones(p_driver?: string | null) {
  const { data, error } = await supabase.rpc("refresh_driver_referral_milestones", { p_driver: p_driver ?? null });
  if (error) throw error;
  return data as number;
}

// CSV export (browser-side)
export function downloadStatementCsv(statement: PayoutStatement, items: PayoutStatementItem[]) {
  const header = ["item_type", "driver_user_id", "amount_gnf", "description", "source_id", "created_at"];
  const rows = items.map(i => [
    i.item_type, i.driver_user_id ?? "", String(i.amount_gnf),
    (i.description ?? "").replace(/"/g, '""'),
    i.source_id ?? "", i.created_at,
  ]);
  const csv = [header, ...rows].map(r => r.map(c => `"${c}"`).join(",")).join("\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `releve-${statement.id.slice(0, 8)}-${statement.period_start}_${statement.period_end}.csv`;
  document.body.appendChild(a); a.click(); a.remove();
  URL.revokeObjectURL(url);
}