/**
 * CHOPCHOP Support / Issues — typed helpers.
 *
 * These helpers wrap the `support_issues` Supabase table.
 *
 * Design rules:
 *   - All helpers respect RLS — they never bypass it. Reads return what
 *     the caller is allowed to see; writes are scoped to the authenticated
 *     user (or admin).
 *   - `createSupportIssue` follows a never-throw contract so it can be
 *     attached to existing operational flows (mission report, payment
 *     receipt, order issues) without crashing the host flow if the issue
 *     write fails.
 *   - Admin-only mutations (status / severity / assigned role / resolve /
 *     escalate) DO throw, because they are explicit operator actions.
 *   - This module NEVER mutates payments, wallets, missions, orders or
 *     dispatch. It is a passive operational log.
 */

import { supabase } from "@/integrations/supabase/client";
import {
  defaultIssueRole,
  defaultIssueSeverity,
  defaultIssueTitle,
  type IssueRole,
  type IssueSeverity,
  type IssueStatus,
  type IssueType,
} from "./constants";

export interface SupportIssue {
  id: string;
  issue_type: IssueType;
  status: IssueStatus;
  severity: IssueSeverity;
  title: string;
  description: string | null;
  district: string | null;
  reporter_user_id: string | null;
  assigned_role: IssueRole;
  related_mission_id: string | null;
  related_payment_intent_id: string | null;
  related_food_order_id: string | null;
  related_market_listing_id: string | null;
  related_store_id: string | null;
  related_restaurant_id: string | null;
  related_driver_id: string | null;
  related_customer_id: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  resolved_at: string | null;
}

export interface CreateIssueInput {
  type: IssueType;
  title?: string;
  description?: string | null;
  district?: string | null;
  severity?: IssueSeverity;
  assignedRole?: IssueRole;
  relatedMissionId?: string | null;
  relatedPaymentIntentId?: string | null;
  relatedFoodOrderId?: string | null;
  relatedMarketListingId?: string | null;
  relatedStoreId?: string | null;
  relatedRestaurantId?: string | null;
  relatedDriverId?: string | null;
  relatedCustomerId?: string | null;
  metadata?: Record<string, unknown>;
}

/** Look up the current auth user id, returning null when signed out. */
async function currentUserId(): Promise<string | null> {
  const { data } = await supabase.auth.getUser();
  return data.user?.id ?? null;
}

/**
 * Create a support issue. Never throws — returns the row on success or
 * null on any failure (RLS, network, missing user, etc.).
 *
 * Intended for opportunistic attachment to existing flows where the host
 * action must complete even if the issue log fails.
 */
export async function createSupportIssue(
  input: CreateIssueInput,
): Promise<SupportIssue | null> {
  try {
    const reporter = await currentUserId();
    if (!reporter) return null;
    const row = {
      reporter_user_id: reporter,
      issue_type: input.type,
      title: input.title ?? defaultIssueTitle(input.type),
      description: input.description ?? null,
      district: input.district ?? null,
      severity: input.severity ?? defaultIssueSeverity(input.type),
      assigned_role: input.assignedRole ?? defaultIssueRole(input.type),
      related_mission_id: input.relatedMissionId ?? null,
      related_payment_intent_id: input.relatedPaymentIntentId ?? null,
      related_food_order_id: input.relatedFoodOrderId ?? null,
      related_market_listing_id: input.relatedMarketListingId ?? null,
      related_store_id: input.relatedStoreId ?? null,
      related_restaurant_id: input.relatedRestaurantId ?? null,
      related_driver_id: input.relatedDriverId ?? null,
      related_customer_id: input.relatedCustomerId ?? null,
      metadata: input.metadata ?? {},
    };
    const { data, error } = await (supabase as any)
      .from("support_issues")
      .insert(row)
      .select("*")
      .single();
    if (error || !data) {
      if (typeof console !== "undefined") {
        // eslint-disable-next-line no-console
        console.warn("[support] createSupportIssue failed", error?.message);
      }
      return null;
    }
    return data as SupportIssue;
  } catch (e) {
    if (typeof console !== "undefined") {
      // eslint-disable-next-line no-console
      console.warn("[support] createSupportIssue threw", e);
    }
    return null;
  }
}

/** List issues the current user reported themselves. */
export async function listMyIssues(limit = 50): Promise<SupportIssue[]> {
  const uid = await currentUserId();
  if (!uid) return [];
  const { data, error } = await (supabase as any)
    .from("support_issues")
    .select("*")
    .eq("reporter_user_id", uid)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) return [];
  return (data ?? []) as SupportIssue[];
}

export interface AdminIssuesFilters {
  status?: IssueStatus | "all";
  type?: IssueType | "all";
  severity?: IssueSeverity | "all";
  district?: string | "all";
  assignedRole?: IssueRole | "all";
  limit?: number;
}

/** Admin-scoped list. Relies on the "Admins read all issues" RLS policy. */
export async function listAdminIssues(
  filters: AdminIssuesFilters = {},
): Promise<SupportIssue[]> {
  let q = (supabase as any)
    .from("support_issues")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(filters.limit ?? 200);
  if (filters.status && filters.status !== "all") q = q.eq("status", filters.status);
  if (filters.type && filters.type !== "all") q = q.eq("issue_type", filters.type);
  if (filters.severity && filters.severity !== "all") q = q.eq("severity", filters.severity);
  if (filters.district && filters.district !== "all") q = q.eq("district", filters.district);
  if (filters.assignedRole && filters.assignedRole !== "all")
    q = q.eq("assigned_role", filters.assignedRole);
  const { data, error } = await q;
  if (error) return [];
  return (data ?? []) as SupportIssue[];
}

export async function getSupportIssue(id: string): Promise<SupportIssue | null> {
  const { data, error } = await (supabase as any)
    .from("support_issues")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error || !data) return null;
  return data as SupportIssue;
}

/**
 * Update an issue status. Admin-only via RLS — throws on failure so the
 * caller can surface a toast.
 */
export async function updateIssueStatus(
  id: string,
  status: IssueStatus,
): Promise<SupportIssue> {
  const { data, error } = await (supabase as any)
    .from("support_issues")
    .update({ status })
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw error;
  return data as SupportIssue;
}

export async function updateIssueSeverity(
  id: string,
  severity: IssueSeverity,
): Promise<SupportIssue> {
  const { data, error } = await (supabase as any)
    .from("support_issues")
    .update({ severity })
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw error;
  return data as SupportIssue;
}

export async function assignIssueRole(
  id: string,
  role: IssueRole,
): Promise<SupportIssue> {
  const { data, error } = await (supabase as any)
    .from("support_issues")
    .update({ assigned_role: role })
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw error;
  return data as SupportIssue;
}

export async function resolveIssue(id: string): Promise<SupportIssue> {
  return updateIssueStatus(id, "resolved");
}

export async function escalateIssue(id: string): Promise<SupportIssue> {
  return updateIssueStatus(id, "escalated");
}