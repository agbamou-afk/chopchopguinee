/**
 * Node 3 — Repas R6 custody client helpers.
 *
 * All secrets stay server-side: one-time handover codes live encrypted in the
 * platform vault and are only ever returned to their designated holder through
 * `repas_custody_code_view`. Nothing here persists a code locally.
 */
import { supabase } from "@/integrations/supabase/client";

export type CustodyKind =
  | "restaurant_handoff"
  | "customer_delivery"
  | "customer_pickup";

export interface CustodyCodeView {
  issued: boolean;
  kind: CustodyKind;
  /** Present only for the holder while the credential is live. */
  code?: string | null;
  expired?: boolean;
  active?: boolean;
  disputed?: boolean;
  consumed?: boolean;
  locked?: boolean;
  attempts?: number;
  attempts_left?: number;
}

export interface CustodyStatus {
  order_id: string;
  order_state: string;
  fulfillment: string;
  credentials: Array<{
    kind: CustodyKind;
    issued: boolean;
    consumed: boolean;
    locked: boolean;
    attempts: number;
    holder_is_self: boolean;
  }>;
  events: Array<{
    boundary: string;
    method: string;
    occurred_at: string;
    actor_user_id: string;
  }>;
}

/** Server soft-refusal (wrong code) — no state or money moved. */
export interface CustodyRefusal {
  ok: false;
  error: string;
  attempts: number;
  attempts_left: number;
  locked: boolean;
}
export interface CustodySuccess {
  ok: true;
  [k: string]: unknown;
}
export type CustodyResult = CustodySuccess | CustodyRefusal;

export function isRefusal(r: CustodyResult): r is CustodyRefusal {
  return r.ok === false;
}

export async function fetchCustodyCode(
  orderId: string,
  kind: CustodyKind,
): Promise<CustodyCodeView> {
  const { data, error } = await (supabase as any).rpc("repas_custody_code_view", {
    p_order_id: orderId,
    p_kind: kind,
  });
  if (error) throw new Error(translateCustodyError(error.message));
  return data as CustodyCodeView;
}

export async function fetchCustodyStatus(orderId: string): Promise<CustodyStatus> {
  const { data, error } = await (supabase as any).rpc("repas_custody_status", {
    p_order_id: orderId,
  });
  if (error) throw new Error(translateCustodyError(error.message));
  return data as CustodyStatus;
}

export async function confirmRepasHandoff(
  missionId: string,
  photoPath: string,
  code: string,
): Promise<CustodyResult> {
  const { data, error } = await (supabase as any).rpc("repas_custody_confirm_handoff", {
    p_mission_id: missionId,
    p_photo_path: photoPath,
    p_code: code.trim(),
  });
  if (error) throw new Error(translateCustodyError(error.message));
  return data as CustodyResult;
}

export async function confirmRepasDelivery(
  missionId: string,
  photoPath: string,
  code: string,
): Promise<CustodyResult> {
  const { data, error } = await (supabase as any).rpc("repas_custody_confirm_delivery", {
    p_mission_id: missionId,
    p_photo_path: photoPath,
    p_code: code.trim(),
  });
  if (error) throw new Error(translateCustodyError(error.message));
  return data as CustodyResult;
}

export async function confirmRepasPickupCollection(
  orderId: string,
  code: string,
): Promise<CustodyResult> {
  const { data, error } = await (supabase as any).rpc(
    "repas_custody_confirm_pickup_collection",
    { p_order_id: orderId, p_code: code.trim() },
  );
  if (error) throw new Error(translateCustodyError(error.message));
  return data as CustodyResult;
}

export function translateCustodyError(msg: string): string {
  if (msg.includes("NOT_AUTHENTICATED")) return "Connectez-vous.";
  if (msg.includes("CUSTODY_PHOTO_REQUIRED")) return "Une photo est requise.";
  if (msg.includes("CUSTODY_PHOTO_NOT_FOUND"))
    return "Photo introuvable sur le serveur. Réessayez l'envoi.";
  if (msg.includes("CUSTODY_PHOTO_OWNER_MISMATCH"))
    return "Cette photo n'appartient pas à ce coursier.";
  if (msg.includes("CUSTODY_PHOTO_MISSION_MISMATCH"))
    return "Cette photo ne correspond pas à cette mission.";
  if (msg.includes("CUSTODY_PHOTO_PHASE_MISMATCH"))
    return "Cette photo ne correspond pas à cette étape.";
  if (msg.includes("CUSTODY_DISPUTE_BLOCKED"))
    return "Commande en litige — remise bloquée jusqu'à résolution.";
  if (msg.includes("CUSTODY_CODE_NOT_ISSUED")) return "Aucun code n'a encore été émis.";
  if (msg.includes("CUSTODY_CODE_ALREADY_USED")) return "Ce code a déjà été utilisé.";
  if (msg.includes("CUSTODY_CODE_LOCKED"))
    return "Code bloqué après 5 tentatives. Contactez le support.";
  if (msg.includes("CUSTODY_CODE_REQUIRED")) return "Saisissez le code de remise.";
  if (msg.includes("CUSTODY_CODE_FORBIDDEN")) return "Ce code ne vous appartient pas.";
  if (msg.includes("CUSTODY_NOT_ESTABLISHED"))
    return "La remise restaurant → coursier n'a pas été confirmée.";
  if (msg.includes("NOT_ASSIGNED_COURIER")) return "Vous n'êtes pas le coursier assigné.";
  if (msg.includes("INVALID_MISSION_STATE")) return "Étape invalide pour cette action.";
  if (msg.includes("ORDER_NOT_READY")) return "La commande n'est pas encore prête.";
  if (msg.includes("ORDER_TERMINAL")) return "Cette commande est déjà clôturée.";
  if (msg.includes("PICKUP_MUST_BE_MISSIONLESS")) return "Cette commande est en livraison.";
  if (msg.includes("NOT_A_PICKUP_ORDER")) return "Cette commande n'est pas un retrait.";
  if (msg.includes("NOT_A_DELIVERY_ORDER")) return "Cette commande n'est pas une livraison.";
  if (msg.includes("NOT_AUTHORIZED")) return "Action non autorisée.";
  return msg;
}

export function refusalMessage(r: CustodyRefusal): string {
  if (r.locked) return "Code bloqué après 5 tentatives. Contactez le support.";
  return `Code incorrect — ${r.attempts_left} tentative${r.attempts_left > 1 ? "s" : ""} restante${r.attempts_left > 1 ? "s" : ""}.`;
}
