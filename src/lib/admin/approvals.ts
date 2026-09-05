import { supabase } from "@/integrations/supabase/client";
import { requiresApproval } from "./permissions";

/**
 * G2 — the browser is NEVER authority.
 *
 * Every helper here is an *advisory mirror* of the server-side constitutional
 * law implemented in `public.admin_enforce` / `public.admin_request_approval` /
 * `public.admin_review_approval`. The database refuses APPROVAL_REQUIRED
 * capabilities without a matching, unexpired, unconsumed approval regardless of
 * what this file does, so nothing here can grant or bypass authority.
 */

/** Ask the server whether the current caller holds a constitutional capability. */
export async function hasCapability(capability: string): Promise<boolean> {
  const { data, error } = await (supabase.rpc as any)("admin_capability", {
    _capability: capability,
  });
  if (error) return false;
  return data === true;
}

/** Server-side capability mode: 'allow' | 'approval_required' | 'read' | null. */
export async function capabilityMode(capability: string): Promise<string | null> {
  const { data, error } = await (supabase.rpc as any)("admin_capability_mode", {
    _capability: capability,
  });
  if (error) return null;
  return (data as string | null) ?? null;
}

/**
 * Create a server-bound approval request. The server derives the intent hash
 * from capability + target + material params; a second God Admin must approve
 * it, and it can be consumed exactly once before it expires.
 */
export async function requestApproval(params: {
  capability: string;
  targetType?: string | null;
  targetId?: string | null;
  material?: Record<string, unknown>;
  module?: string;
  ttlMinutes?: number;
}): Promise<string> {
  const { data, error } = await (supabase.rpc as any)("admin_request_approval", {
    _capability: params.capability,
    _target_type: params.targetType ?? null,
    _target_id: params.targetId ?? null,
    _material: params.material ?? {},
    _module: params.module ?? "admin",
    _ttl_minutes: params.ttlMinutes ?? 1440,
  });
  if (error) throw error;
  return data as string;
}

/** Approve or reject a pending request. Requester != approver is enforced server-side. */
export async function reviewApproval(params: {
  approvalId: string;
  decision: "approved" | "rejected";
  note?: string;
}) {
  const { error } = await (supabase.rpc as any)("admin_review_approval", {
    _approval_id: params.approvalId,
    _decision: params.decision,
    _note: params.note ?? null,
  });
  if (error) throw error;
}

/**
 * Advisory convenience: run `execute` when the action does not need approval.
 * The server still re-checks; a wrong answer here cannot bypass anything.
 */
export async function requireApprovalOr<T>(params: {
  capability: string;
  action?: string;
  targetType?: string | null;
  targetId?: string | null;
  material?: Record<string, unknown>;
  module?: string;
  execute: () => Promise<T>;
}): Promise<{ executed: true; result: T } | { executed: false; approvalId: string }> {
  const mode = await capabilityMode(params.capability);
  const needsApproval =
    mode === "approval_required" || requiresApproval(params.action ?? params.capability);
  if (!needsApproval) {
    const result = await params.execute();
    return { executed: true, result };
  }
  const approvalId = await requestApproval(params);
  return { executed: false, approvalId };
}

/** Mirror-only audit note. Canonical provenance is written by `admin_enforce`. */
export async function logAction(params: {
  module: string;
  action: string;
  target_type?: string;
  target_id?: string;
  before?: unknown;
  after?: unknown;
  note?: string;
}) {
  await (supabase.rpc as any)("log_admin_action", {
    _module: params.module,
    _action: params.action,
    _target_type: params.target_type ?? null,
    _target_id: params.target_id ?? null,
    _before: params.before ?? null,
    _after: params.after ?? null,
    _note: params.note ?? null,
  });
}
