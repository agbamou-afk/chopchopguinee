import { supabase } from "@/integrations/supabase/client";
import type {
  PackageCategory,
  PackageCheckoutResult,
  PackageClaimOutcome,
  PackageDelivery,
  PackageQuote,
  PackageRuntime,
  PackageSecrets,
  PackageTender,
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
  /** Slice 6 — required once `envoyer_declared_value_enabled` is ON. */
  declaredValueGnf?: number | null;
  tender?: PackageTender | null;
  valueAttested?: boolean;
  attestationStatement?: string | null;
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
    p_declared_value_gnf: input.declaredValueGnf ?? null,
    p_tender: input.tender ?? null,
    p_value_attested: input.valueAttested ?? false,
    p_attestation_statement: input.attestationStatement ?? null,
  });
  if (error) throw error;
  return data as PackageCheckoutResult;
}

/* ── Slice 6 — declared value, evidence and claims ───────────────────── */

export interface EnvoyerPolicy {
  max_declared_value_gnf: number | null;
  claims_exposure_max_gnf: number | null;
  collateral_pct_bps: number | null;
  transaction_fee_bps: number | null;
}

/** Authoritative Envoyer policy in force now (ceiling, collateral, fee). */
export async function getEnvoyerPolicy(): Promise<EnvoyerPolicy | null> {
  const { data, error } = await (supabase as any).rpc("finance_policy_at", {
    p_mission_type: "envoyer",
  });
  if (error) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return (row ?? null) as EnvoyerPolicy | null;
}

/**
 * Uploads shipment photos to the private `package-evidence` bucket and
 * registers them against the quote. The storage path shape is enforced
 * server-side: `<uid>/<quote_id>/<file>`.
 */
export async function uploadPackageEvidence(
  quoteId: string,
  files: File[],
  kind: "item" | "packaging" | "label" | "condition" = "item",
): Promise<number> {
  const { data: auth } = await supabase.auth.getUser();
  const uid = auth?.user?.id;
  if (!uid) throw new Error("not_authenticated");
  let count = 0;
  for (const file of files) {
    const ext = (file.name.split(".").pop() || "jpg").toLowerCase().slice(0, 5);
    const name =
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? `${crypto.randomUUID()}.${ext}`
        : `${Date.now()}-${Math.random().toString(16).slice(2)}.${ext}`;
    const path = `${uid}/${quoteId}/${name}`;
    const up = await supabase.storage
      .from("package-evidence")
      .upload(path, file, { contentType: file.type || "image/jpeg", upsert: false });
    if (up.error) throw up.error;
    const { error } = await (supabase as any).rpc("package_evidence_register", {
      p_quote_id: quoteId,
      p_storage_path: path,
      p_kind: kind,
      p_content_type: file.type || null,
      p_byte_size: file.size ?? null,
    });
    if (error) throw error;
    count += 1;
  }
  return count;
}

/** Runtime economics of one package (participants + admins, via RLS). */
export async function getPackageRuntime(packageId: string): Promise<PackageRuntime | null> {
  const { data, error } = await (supabase as any)
    .from("package_runtime")
    .select("*")
    .eq("package_id", packageId)
    .maybeSingle();
  if (error) return null;
  return (data ?? null) as PackageRuntime | null;
}

/** Runtime for the courier's current mission (driver_user_id = auth.uid()). */
export async function getPackageRuntimeByMission(missionId: string): Promise<PackageRuntime | null> {
  const { data, error } = await (supabase as any)
    .from("package_runtime")
    .select("*")
    .eq("mission_id", missionId)
    .maybeSingle();
  if (error) return null;
  return (data ?? null) as PackageRuntime | null;
}

/** Sender-only. Requires established custody (verified pickup). */
export async function openPackageClaim(
  packageId: string,
  reason: string,
  evidenceRef?: string | null,
) {
  const { data, error } = await (supabase as any).rpc("package_claim_open", {
    p_package_id: packageId,
    p_reason: reason,
    p_evidence_ref: evidenceRef ?? null,
  });
  if (error) throw error;
  return data as Record<string, unknown>;
}

/** Admin queue: every package with an active or resolved claim. */
export async function listPackageClaims(openOnly = true): Promise<PackageRuntime[]> {
  let q = (supabase as any)
    .from("package_runtime")
    .select("*")
    .neq("claim_state", "none")
    .order("claim_opened_at", { ascending: true })
    .limit(100);
  if (openOnly) q = q.eq("claim_state", "open");
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as PackageRuntime[];
}

/** God-Admin only — enforced server-side by `is_god_admin`. */
export async function resolvePackageClaim(input: {
  packageId: string;
  outcome: PackageClaimOutcome;
  reason: string;
  evidenceRef: string;
  payCustomerGnf?: number;
}) {
  const { data, error } = await (supabase as any).rpc("admin_package_claim_resolve", {
    p_package_id: input.packageId,
    p_outcome: input.outcome,
    p_reason: input.reason,
    p_evidence_ref: input.evidenceRef,
    p_pay_customer_gnf: input.payCustomerGnf ?? 0,
  });
  if (error) throw error;
  return data as Record<string, unknown>;
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

/** Single package row (sender-only via RLS). Used for payment/status polling. */
export async function getPackageDelivery(packageId: string): Promise<PackageDelivery | null> {
  const { data, error } = await (supabase as any)
    .from("package_deliveries")
    .select("*")
    .eq("id", packageId)
    .maybeSingle();
  if (error) return null;
  return (data ?? null) as PackageDelivery | null;
}

export interface ReceivingAccount {
  id: string;
  provider: string;
  label: string;
  phone_e164: string;
  public_instructions: string | null;
}

/** Active Orange Money receiving accounts (admin-configured, sanitized RPC). */
export async function listReceivingAccounts(): Promise<ReceivingAccount[]> {
  const { data, error } = await (supabase as any).rpc("get_active_payment_receiving_accounts");
  if (error) return [];
  return ((data ?? []) as ReceivingAccount[]).filter((a) => a.provider === "orange_money");
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

export interface PackageCancelPreview {
  already_cancelled: boolean;
  self_service: boolean;
  courier_assigned?: boolean;
  reason?: string;
  fee_gnf: number;
  refund_gnf: number;
  paid?: boolean;
}

/** Read-only: exact fee/refund before the sender confirms a cancellation. */
export async function previewPackageCancel(packageId: string): Promise<PackageCancelPreview> {
  const { data, error } = await (supabase as any).rpc("package_delivery_cancel_preview", {
    p_package_id: packageId,
  });
  if (error) throw error;
  return data as PackageCancelPreview;
}

/** Admin (god / operations): grant or revoke one driver capability. */
export async function adminSetDriverCapability(
  driverUserId: string,
  capability: string,
  grant: boolean,
) {
  const { data, error } = await (supabase as any).rpc("admin_set_driver_capability", {
    _driver_user_id: driverUserId,
    _capability: capability,
    _grant: grant,
  });
  if (error) throw error;
  return data as { user_id: string; capabilities: string[] };
}

/** Shared shape of both verification RPCs. `ok:false` is a normal outcome. */
export interface PackageVerifyResult {
  ok: boolean;
  idempotent: boolean;
  mission_state: string;
  error?: "invalid_code" | "too_many_attempts";
  attempts?: number;
  attempts_left?: number;
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

export async function verifyPackagePickup(
  packageId: string,
  code: string,
): Promise<PackageVerifyResult> {
  const { data, error } = await (supabase as any).rpc("package_verify_pickup", {
    p_package_id: packageId,
    p_code: code,
  });
  if (error) throw error;
  return data as PackageVerifyResult;
}

export async function verifyPackageDelivery(
  packageId: string,
  code: string,
  recipientName?: string | null,
): Promise<PackageVerifyResult> {
  const { data, error } = await (supabase as any).rpc("package_verify_delivery", {
    p_package_id: packageId,
    p_code: code,
    p_recipient_name: recipientName ?? null,
  });
  if (error) throw error;
  return data as PackageVerifyResult;
}