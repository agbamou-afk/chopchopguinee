import { supabase } from "@/integrations/supabase/client";

/**
 * Node 4 — Marché R7: shopper-driver fulfillment client surface.
 *
 * THIN client. Every lifecycle state, monetary value, verification verdict and
 * authority check below is produced by the server RPCs. The client never
 * computes a spend, never advances a state locally and never settles anything.
 */

export type ShopperMissionState =
  | "unassigned"
  | "assigned"
  | "at_market"
  | "shopping"
  | "purchase_verified"
  | "delivering"
  | "completed"
  | "cancelled";

export type ShopperLineState =
  | "pending"
  | "acquired"
  | "unavailable"
  | "substitution_proposed";

export interface ShopperMissionLine {
  line_no: number;
  commodity_name_fr: string;
  variant_name_fr: string;
  option_label_fr: string;
  sale_unit: string;
  canonical_base_unit: string | null;
  requested_qty: number;
  normalized_quantity: number | null;
  state: ShopperLineState;
  actual_qty: number | null;
  actual_normalized_quantity: number | null;
  actual_unit_price_gnf: number | null;
  actual_line_total_gnf: number | null;
  substitute_label_fr: string | null;
  note_fr: string | null;
  proposal_version: number;
  pending_proposal: {
    version: number;
    kind: string;
    payload: Record<string, unknown> | null;
    proposed_at: string;
  } | null;
}

export interface ShopperMission {
  request_id: string;
  state: ShopperMissionState;
  market_id: string | null;
  destination_address: string | null;
  shopper_user_id: string | null;
  has_shopper: boolean;
  buyer_user_id: string | null;
  mission_id: string | null;
  authorized_ceiling_gnf: number;
  verified_spend_gnf: number | null;
  actual_spend_gnf: number | null;
  request_status: string;
  assigned_at: string | null;
  arrived_market_at: string | null;
  shopping_started_at: string | null;
  purchase_submitted_at: string | null;
  purchase_verified_at: string | null;
  delivery_started_at: string | null;
  delivered_at: string | null;
  completed_at: string | null;
  evidence_count: number;
  lines: ShopperMissionLine[];
  replayed?: boolean;
  /** Server refusal envelope: spend exceeds the customer's authorization. */
  code?: string;
  required_ceiling_gnf?: number;
  settlement?: {
    captured_gnf: number;
    released_gnf: number;
  };
}

export interface AvailableBasket {
  request_id: string;
  authorized_ceiling_gnf: number;
  line_count: number;
  item_count: number;
  authorized_at: string;
  destination_address: string | null;
}

type RpcClient = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
const rpc = supabase as unknown as RpcClient;

async function call<T>(name: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await rpc.rpc(name, args);
  if (error) throw new Error((error as { message?: string })?.message || "PROCUREMENT_ERROR");
  return data as T;
}

/* ---------------- shopper (driver) authority ---------------- */

export const listAvailableBaskets = (limit = 20) =>
  call<AvailableBasket[]>("marche_shopper_available_baskets", { p_limit: limit });

export const claimBasket = (requestId: string) =>
  call<ShopperMission>("marche_shopper_claim", { p_request_id: requestId });

export const arriveAtMarket = (requestId: string, marketId: string | null = null) =>
  call<ShopperMission>("marche_shopper_arrive_market", {
    p_request_id: requestId,
    p_market_id: marketId,
  });

export const startShopping = (requestId: string) =>
  call<ShopperMission>("marche_shopper_start_shopping", { p_request_id: requestId });

export interface ResolveLineInput {
  requestId: string;
  lineNo: number;
  kind: "acquired" | "unavailable" | "propose_substitution";
  actualQty?: number;
  actualUnitPriceGnf?: number;
  substituteLabelFr?: string;
  noteFr?: string;
}

export const resolveLine = (input: ResolveLineInput) =>
  call<ShopperMission>("marche_shopper_resolve_line", {
    p: {
      request_id: input.requestId,
      line_no: input.lineNo,
      kind: input.kind,
      actual_qty: input.actualQty ?? null,
      actual_unit_price_gnf: input.actualUnitPriceGnf ?? null,
      substitute_label_fr: input.substituteLabelFr ?? null,
      note_fr: input.noteFr ?? null,
    },
  });

export const attachEvidence = (requestId: string, storagePath: string) =>
  call<ShopperMission>("marche_shopper_attach_evidence", {
    p: { request_id: requestId, storage_path: storagePath },
  });

export const submitPurchase = (requestId: string) =>
  call<ShopperMission>("marche_shopper_submit_purchase", { p: { request_id: requestId } });

export const startDelivery = (requestId: string) =>
  call<ShopperMission>("marche_shopper_start_delivery", { p_request_id: requestId });

export const completeDelivery = (requestId: string) =>
  call<ShopperMission>("marche_shopper_complete_delivery", { p_request_id: requestId });

/* ---------------- customer authority ---------------- */

export const getProcurementMission = (requestId: string) =>
  call<ShopperMission | null>("marche_procurement_mission_get", { p_request_id: requestId });

export const setProcurementDestination = (requestId: string, address: string) =>
  call<{ destination_address: string }>("marche_procurement_set_destination", {
    p: { request_id: requestId, destination_address: address },
  });

export const decideProposal = (args: {
  requestId: string;
  lineNo: number;
  version: number;
  decision: "approve" | "reject";
}) =>
  call<ShopperMission>("marche_customer_decide_proposal", {
    p: {
      request_id: args.requestId,
      line_no: args.lineNo,
      version: args.version,
      decision: args.decision,
    },
  });

/* ---------------- evidence upload (private bucket) ---------------- */

export const EVIDENCE_BUCKET = "marche-procurement-evidence";

/** Uploads a receipt photo into the basket's own folder, then links it server-side. */
export async function uploadPurchaseEvidence(requestId: string, file: File): Promise<ShopperMission> {
  const ext = (file.name.split(".").pop() || "jpg").toLowerCase();
  const path = `${requestId}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from(EVIDENCE_BUCKET).upload(path, file, {
    contentType: file.type || "image/jpeg",
    upsert: false,
  });
  if (error) throw new Error(error.message);
  return attachEvidence(requestId, path);
}

/* ---------------- honest French copy ---------------- */

export const MISSION_STATE_LABEL_FR: Record<ShopperMissionState, string> = {
  unassigned: "En attente d'un acheteur",
  assigned: "Acheteur assigné",
  at_market: "Au marché",
  shopping: "Achats en cours",
  purchase_verified: "Achats vérifiés",
  delivering: "Livraison en cours",
  completed: "Terminée",
  cancelled: "Annulée",
};

export const LINE_STATE_LABEL_FR: Record<ShopperLineState, string> = {
  pending: "À acheter",
  acquired: "Acheté",
  unavailable: "Indisponible au marché",
  substitution_proposed: "Remplacement proposé",
};

/** Machine-readable server refusals mapped to honest customer/shopper copy. */
export function shopperErrorFr(message: string): string {
  const m = (message || "").toUpperCase();
  if (m.includes("PROCUREMENT_SHOPPER_NOT_ELIGIBLE"))
    return "Vous n'avez pas la capacité « Acheteur Marché ». Contactez le support CHOP CHOP.";
  if (m.includes("PROCUREMENT_MISSION_ALREADY_ASSIGNED"))
    return "Ce panier vient d'être pris par un autre acheteur.";
  if (m.includes("PROCUREMENT_NOT_ASSIGNED_SHOPPER"))
    return "Vous n'êtes pas l'acheteur assigné à ce panier.";
  if (m.includes("PROCUREMENT_APPROVAL_REQUIRED"))
    return "Cette modification doit d'abord être proposée au client.";
  if (m.includes("PROCUREMENT_APPROVAL_PENDING"))
    return "En attente de la réponse du client sur le remplacement proposé.";
  if (m.includes("PROCUREMENT_PROPOSAL_STALE"))
    return "Cette proposition n'est plus à jour. Actualisez avant de répondre.";
  if (m.includes("PROCUREMENT_PROPOSAL_ALREADY_DECIDED"))
    return "Cette proposition a déjà reçu une réponse.";
  if (m.includes("PROCUREMENT_ACTUAL_PRICE_REQUIRED"))
    return "Saisissez le prix réellement payé au marché.";
  if (m.includes("PROCUREMENT_EVIDENCE_PATH_INVALID"))
    return "Ce reçu n'appartient pas à ce panier.";
  if (m.includes("PROCUREMENT_EVIDENCE_REQUIRED"))
    return "Ajoutez une photo du reçu avant de valider les achats.";
  if (m.includes("PROCUREMENT_LINES_UNRESOLVED"))
    return "Chaque article doit être marqué acheté ou indisponible.";
  if (m.includes("PROCUREMENT_PURCHASE_VERIFICATION_REQUIRED"))
    return "Les achats doivent être vérifiés avant la livraison.";
  if (m.includes("PROCUREMENT_AUTHORIZATION_REQUIRED"))
    return "La dépense dépasse le montant autorisé par le client.";
  if (m.includes("PROCUREMENT_ILLEGAL_TRANSITION")) return "Cette étape n'est pas possible maintenant.";
  if (m.includes("PROCUREMENT_NOT_AUTHORIZED")) return "Action non autorisée.";
  if (m.includes("PROCUREMENT_NOT_FOUND")) return "Panier introuvable.";
  if (m.includes("PROCUREMENT_AUTH_REQUIRED")) return "Connectez-vous pour continuer.";
  return "Action refusée par CHOP CHOP.";
}
