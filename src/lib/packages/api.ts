import { supabase } from "@/integrations/supabase/client";
import type {
  PackageCategory,
  PackageCheckoutResult,
  PackageDelivery,
  PackageQuote,
  PackageSecrets,
} from "./types";

/**
 * Thin, honest wrappers around the Envoyer RPCs. No pricing, no state
 * machine and no verification logic lives here — the server owns all of it.
 */

export async function requestPackageQuote(input: {
  pickup: { lat: number; lng: number; label?: string | null };
  destination: { lat: number; lng: number; label?: string | null };
  category: PackageCategory;
}): Promise<PackageQuote> {
  const { data, error } = await (supabase as any).rpc("package_delivery_quote", {
    p_pickup_lat: input.pickup.lat,
    p_pickup_lng: input.pickup.lng,
    p_dest_lat: input.destination.lat,
    p_dest_lng: input.destination.lng,
    p_category: input.category,
    p_pickup_label: input.pickup.label ?? null,
    p_dest_label: input.destination.label ?? null,
  });
  if (error) throw error;
  return data as PackageQuote;
}

export async function createPackageCheckout(input: {
  quoteId: string;
  recipientName: string;
  recipientPhone: string;
  description?: string | null;
  instructions?: string | null;
  senderPhone?: string | null;
  idempotencyKey: string;
  sandbox?: boolean;
  testRunId?: string | null;
}): Promise<PackageCheckoutResult> {
  const { data, error } = await (supabase as any).rpc("package_delivery_create_checkout", {
    p_quote_id: input.quoteId,
    p_recipient_name: input.recipientName,
    p_recipient_phone: input.recipientPhone,
    p_description: input.description ?? null,
    p_instructions: input.instructions ?? null,
    p_idempotency_key: input.idempotencyKey,
    p_sender_phone: input.senderPhone ?? null,
    p_provider: "orange_money",
    p_sandbox: input.sandbox ?? false,
    p_test_run_id: input.testRunId ?? null,
  });
  if (error) throw error;
  return data as PackageCheckoutResult;
}

export async function listMyPackageDeliveries(limit = 20): Promise<PackageDelivery[]> {
  const { data, error } = await (supabase as any)
    .from("package_deliveries")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as PackageDelivery[];
}

/** Sender-only: RLS denies every other reader, including the assigned courier. */
export async function getPackageSecrets(packageId: string): Promise<PackageSecrets | null> {
  const { data, error } = await (supabase as any)
    .from("package_delivery_secrets")
    .select("*")
    .eq("package_id", packageId)
    .maybeSingle();
  if (error) return null;
  return (data ?? null) as PackageSecrets | null;
}

export async function cancelPackageDelivery(packageId: string, reason?: string) {
  const { data, error } = await (supabase as any).rpc("package_delivery_cancel", {
    p_package_id: packageId,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  return data as {
    idempotent: boolean;
    self_service: boolean;
    fee_gnf?: number;
    refund_gnf?: number;
    support_issue_id?: string;
  };
}

/** Courier-facing operational payload. Never contains verification codes. */
export async function getCourierPackageView(missionId: string) {
  const { data, error } = await (supabase as any).rpc("package_delivery_courier_view", {
    p_mission_id: missionId,
  });
  if (error) throw error;
  return data as {
    package_id: string;
    reference: string;
    category: string;
    description: string | null;
    handling_notes: string | null;
    pickup_label: string | null;
    destination_label: string | null;
    sender_phone: string | null;
    recipient_name: string;
    recipient_phone: string;
    package_status: string;
    is_sandbox: boolean;
  } | null;
}

export async function verifyPackagePickup(packageId: string, code: string) {
  const { data, error } = await (supabase as any).rpc("package_verify_pickup", {
    p_package_id: packageId,
    p_code: code,
  });
  if (error) throw error;
  return data as { ok: boolean; idempotent: boolean; mission_state: string };
}

export async function verifyPackageDelivery(
  packageId: string,
  code: string,
  recipientName?: string | null,
) {
  const { data, error } = await (supabase as any).rpc("package_verify_delivery", {
    p_package_id: packageId,
    p_code: code,
    p_recipient_name: recipientName ?? null,
  });
  if (error) throw error;
  return data as { ok: boolean; idempotent: boolean; mission_state: string };
}