import { supabase } from "@/integrations/supabase/client";
import { requiresApproval } from "./permissions";

export async function requestApproval(params: {
  module: string;
  action: string;
  payload?: Record<string, unknown>;
}) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Not authenticated");
  const { data, error } = await supabase
    .from("approval_requests")
    .insert({
      requested_by: user.id,
      module: params.module,
      action: params.action,
      payload: (params.payload ?? {}) as any,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Run `execute` directly if the action does not need approval; otherwise enqueue it. */
export async function requireApprovalOr<T>(params: {
  module: string;
  action: string;
  payload?: Record<string, unknown>;
  execute: () => Promise<T>;
}): Promise<{ executed: true; result: T } | { executed: false; approvalId: string }> {
  if (!requiresApproval(params.action)) {
    const result = await params.execute();
    return { executed: true, result };
  }
  const req = await requestApproval(params);
  return { executed: false, approvalId: req.id };
}

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