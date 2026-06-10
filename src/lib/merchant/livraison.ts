/**
 * Phase 3 — Marketplace → CHOP Livraison bridge.
 *
 * Client wrapper around the SECURITY DEFINER RPC
 * `marketplace_create_delivery_mission`. The RPC enforces:
 *   - caller is the merchant on the offer
 *   - the offer is in 'accepted' status
 *   - the merchant store is (active, approved)
 *   - pickup coordinates come from the merchant store
 *   - idempotent: a second call for the same offer returns the existing mission
 */
import { supabase } from "@/integrations/supabase/client";

export interface DeliveryMission {
  id: string;
  type: string;
  state: string;
  courier_id: string | null;
  customer_id: string;
  merchant_id: string | null;
  merchant_store_id: string | null;
  ref_market_order_id: string | null;
  pickup_address: string | null;
  pickup_lat: number | null;
  pickup_lng: number | null;
  dropoff_address: string | null;
  dropoff_lat: number | null;
  dropoff_lng: number | null;
  payload_summary: string | null;
  estimated_earning_gnf: number;
  merchant_handoff_code: string | null;
  pickup_photo_url: string | null;
  delivery_photo_url: string | null;
  pickup_confirmed_at: string | null;
  pickup_confirmed_by: string | null;
  dropoff_confirmed_at: string | null;
  dropoff_confirmed_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface CreateMarketplaceDeliveryInput {
  offerId: string;
  dropoffAddress: string;
  dropoffLat: number;
  dropoffLng: number;
  payloadSummary: string;
  estimatedEarningGnf?: number;
  dropoffNotes?: string | null;
}

export async function createMarketplaceDeliveryMission(
  input: CreateMarketplaceDeliveryInput,
): Promise<DeliveryMission> {
  const { data, error } = await (supabase as any).rpc(
    "marketplace_create_delivery_mission",
    {
      _offer_id: input.offerId,
      _dropoff_address: input.dropoffAddress,
      _dropoff_lat: input.dropoffLat,
      _dropoff_lng: input.dropoffLng,
      _payload_summary: input.payloadSummary,
      _estimated_earning_gnf: Math.max(0, Math.round(input.estimatedEarningGnf ?? 0)),
      _dropoff_notes: input.dropoffNotes ?? null,
    },
  );
  if (error) throw new Error(translateLivraisonError(error.message));
  return data as DeliveryMission;
}

/** Fetch the Livraison mission for an offer, if one exists. */
export async function getMissionForOffer(offerId: string): Promise<DeliveryMission | null> {
  const { data } = await (supabase as any)
    .from("missions")
    .select("*")
    .eq("ref_market_order_id", offerId)
    .maybeSingle();
  return (data as DeliveryMission | null) ?? null;
}

function translateLivraisonError(msg: string): string {
  if (msg.includes("not_authenticated")) return "Connectez-vous pour demander la livraison.";
  if (msg.includes("offer_not_found")) return "Commande introuvable.";
  if (msg.includes("not_merchant_on_offer")) return "Vous n'êtes pas le marchand de cette commande.";
  if (msg.includes("offer_not_accepted")) return "La commande doit être acceptée avant la livraison.";
  if (msg.includes("offer_missing_store")) return "Aucune boutique associée à cette commande.";
  if (msg.includes("store_not_found")) return "Boutique introuvable.";
  if (msg.includes("store_not_active_approved")) return "Votre boutique doit être approuvée et active.";
  if (msg.includes("store_missing_location")) return "Géolocalisez votre boutique avant de demander une livraison.";
  return msg;
}