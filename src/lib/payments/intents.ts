/**
 * Thin client around the `payment_intents` + reconciliation tables.
 * Mutating helpers (confirm/fail/cancel) call SECURITY DEFINER SQL
 * functions that enforce admin-only access server-side.
 */
import { supabase } from "@/integrations/supabase/client";
import type {
  PaymentIntent,
  PaymentProvider,
  PaymentPurpose,
  PaymentReconciliationEvent,
} from "./types";

type Row = Record<string, unknown>;
const cast = <T>(row: Row): T => row as unknown as T;

export interface CreateIntentInput {
  amount_gnf: number;
  purpose: PaymentPurpose;
  provider: PaymentProvider;
  user_id: string;
  provider_reference?: string | null;
  related_order_id?: string | null;
  related_mission_id?: string | null;
  related_listing_id?: string | null;
  related_store_id?: string | null;
  metadata?: Record<string, unknown>;
}

export async function createIntent(input: CreateIntentInput): Promise<PaymentIntent> {
  const { data, error } = await (supabase.from("payment_intents" as never) as any)
    .insert(input)
    .select()
    .single();
  if (error) throw error;
  return cast<PaymentIntent>(data as Row);
}

export async function getIntent(id: string): Promise<PaymentIntent | null> {
  const { data, error } = await (supabase.from("payment_intents" as never) as any)
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data ? cast<PaymentIntent>(data as Row) : null;
}

export async function listIntents(opts: { state?: string; limit?: number } = {}): Promise<PaymentIntent[]> {
  let q = (supabase.from("payment_intents" as never) as any).select("*").order("created_at", { ascending: false });
  if (opts.state) q = q.eq("state", opts.state);
  q = q.limit(opts.limit ?? 100);
  const { data, error } = await q;
  if (error) throw error;
  return ((data ?? []) as Row[]).map((r) => cast<PaymentIntent>(r));
}

export async function confirmIntent(id: string, providerReference?: string, note?: string): Promise<PaymentIntent> {
  const { data, error } = await (supabase as any).rpc("confirm_payment_intent", {
    p_intent_id: id,
    p_provider_reference: providerReference ?? null,
    p_note: note ?? null,
  });
  if (error) throw error;
  return cast<PaymentIntent>(data as Row);
}

export async function failIntent(id: string, reason?: string): Promise<PaymentIntent> {
  const { data, error } = await (supabase as any).rpc("fail_payment_intent", {
    p_intent_id: id,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  return cast<PaymentIntent>(data as Row);
}

export async function cancelIntent(id: string, reason?: string): Promise<PaymentIntent> {
  const { data, error } = await (supabase as any).rpc("cancel_payment_intent", {
    p_intent_id: id,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  return cast<PaymentIntent>(data as Row);
}

export async function listReconciliationEvents(intentId: string): Promise<PaymentReconciliationEvent[]> {
  const { data, error } = await (supabase.from("payment_reconciliation_events" as never) as any)
    .select("*")
    .eq("intent_id", intentId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return ((data ?? []) as Row[]).map((r) => cast<PaymentReconciliationEvent>(r));
}