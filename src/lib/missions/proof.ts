/**
 * Phase 4 — Mission trust layer client helpers.
 *
 * Upload pickup/delivery photo proofs to the private `mission-proofs` bucket
 * and call the SECURITY DEFINER RPCs that enforce:
 *   - photo URL required
 *   - pickup: courier scans merchant QR or types merchant code
 *   - dropoff: courier types the 6-digit code given by the buyer
 *   - customer confirmation closes the loop
 */
import { supabase } from "@/integrations/supabase/client";

const BUCKET = "mission-proofs";

export type ProofKind = "pickup" | "delivery";

export async function uploadMissionProof(
  missionId: string,
  kind: ProofKind,
  file: Blob,
  ext: string = "jpg",
): Promise<string> {
  const path = `${missionId}/${kind}-${Date.now()}.${ext}`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, file, {
    contentType: file.type || "image/jpeg",
    upsert: false,
  });
  if (error) throw new Error(error.message);
  return path;
}

export async function getProofSignedUrl(path: string, expiresSec = 60 * 10): Promise<string | null> {
  const { data } = await supabase.storage.from(BUCKET).createSignedUrl(path, expiresSec);
  return data?.signedUrl ?? null;
}

export async function confirmPickupWithProof(
  missionId: string,
  photoUrl: string,
  merchantCode: string,
) {
  const { data, error } = await (supabase as any).rpc("mission_confirm_pickup_with_proof", {
    _mission_id: missionId,
    _photo_url: photoUrl,
    _merchant_code: merchantCode.trim(),
  });
  if (error) throw new Error(translateProofError(error.message));
  return data;
}

export async function confirmDropoffWithProof(
  missionId: string,
  photoUrl: string,
  customerCode: string,
) {
  const { data, error } = await (supabase as any).rpc("mission_confirm_dropoff_with_proof", {
    _mission_id: missionId,
    _photo_url: photoUrl,
    _customer_code: customerCode.trim(),
  });
  if (error) throw new Error(translateProofError(error.message));
  return data;
}

export async function customerConfirmDelivery(missionId: string) {
  const { data, error } = await (supabase as any).rpc("mission_customer_confirm_delivery", {
    _mission_id: missionId,
  });
  if (error) throw new Error(translateProofError(error.message));
  return data;
}

function translateProofError(msg: string): string {
  if (msg.includes("not_authenticated")) return "Connectez-vous.";
  if (msg.includes("photo_required")) return "Une photo est requise.";
  if (msg.includes("merchant_code_required")) return "Scannez le QR du marchand ou saisissez son code.";
  if (msg.includes("invalid_merchant_code")) return "Code marchand invalide.";
  if (msg.includes("invalid_customer_code")) return "Code client invalide.";
  if (msg.includes("not_delivered_yet")) return "La livraison n'a pas encore été confirmée par le coursier.";
  if (msg.includes("forbidden")) return "Action non autorisée.";
  if (msg.includes("mission_not_found")) return "Mission introuvable.";
  return msg;
}