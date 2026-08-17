import { supabase } from "@/integrations/supabase/client";
import { newOrderRequestUuid } from "@/lib/marche/orderRequestId";

/**
 * Node 4 — Marché R6.5: ChopChop procurement basket + spending authorization.
 *
 * THIN client. Every monetary value, estimate, ceiling bound and authorization
 * state below comes from the server RPCs. The client never computes a price,
 * never decides whether authorization is allowed, and never settles anything.
 */

export type ProcurementEstimateStatus = "available" | "insufficient_data";

/** A basket line: the ONLY fields the server accepts. */
export interface ProcurementLineInput {
  commodity_code: string;
  variant_code: string;
  option_code: string;
  qty: number;
}

export interface ProcurementQuoteLine {
  line_no: number;
  commodity_code: string;
  variant_code: string;
  option_code: string;
  commodity_name_fr: string;
  variant_name_fr: string;
  option_label_fr: string;
  sale_unit: string;
  normalization_kind: "exact" | "unit_native" | "non_comparable";
  canonical_base_unit: string | null;
  canonical_quantity: number | null;
  requested_qty: number;
  normalized_quantity: number | null;
  estimate_source: string | null;
  estimated_unit_price_gnf: number | null;
  estimated_line_total_gnf: number | null;
  estimate_sample_count: number | null;
  sample_count_in_window: number | null;
  min_samples: number | null;
  estimate_unavailable_reason: string | null;
}

export interface ProcurementQuote {
  lines: ProcurementQuoteLine[];
  line_count: number;
  item_count: number;
  currency: string;
  estimate_status: ProcurementEstimateStatus;
  estimate_basis: string | null;
  estimated_subtotal_gnf: number | null;
  estimate_confidence: "low" | "medium" | "high" | null;
  estimate_sample_count: number | null;
  estimate_freshness_hours: number | null;
  estimate_unavailable_reason: string | null;
  min_samples: number | null;
  observation_window_hours: number | null;
  /** Server verdict. The client must never derive this itself. */
  authorization_allowed: boolean;
  min_ceiling_gnf: number | null;
  max_ceiling_gnf: number | null;
  disclaimer_fr: string | null;
}

export interface ProcurementRequest {
  id: string;
  status: "authorized" | "cancelled" | "settled" | string;
  currency: string;
  authorized_ceiling_gnf: number;
  held_total_gnf: number;
  captured_total_gnf: number;
  released_total_gnf: number;
  actual_spend_gnf: number | null;
  estimate_status: string | null;
  estimated_subtotal_gnf: number | null;
  estimate_confidence: string | null;
  line_count: number;
  item_count: number;
  client_request_id: string;
  authorized_at: string | null;
  settled_at: string | null;
  cancelled_at: string | null;
  disclaimer_fr: string | null;
  items: ProcurementQuoteLine[];
  authorizations: {
    seq: number;
    kind: string;
    amount_gnf: number;
    ceiling_before_gnf: number;
    ceiling_after_gnf: number;
    captured_gnf: number | null;
    released_gnf: number | null;
  }[];
  replayed?: boolean;
}

type RpcClient = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
const rpc = supabase as unknown as RpcClient;

function fail(error: unknown): never {
  const e = error as { message?: string } | null;
  throw new Error(e?.message || "PROCUREMENT_ERROR");
}

/** Strips any field the server forbids — the client may only send staple identity + qty. */
export function sanitizeLines(lines: ProcurementLineInput[]): ProcurementLineInput[] {
  return lines.map((l) => ({
    commodity_code: l.commodity_code,
    variant_code: l.variant_code,
    option_code: l.option_code,
    qty: l.qty,
  }));
}

export async function quoteProcurement(lines: ProcurementLineInput[]): Promise<ProcurementQuote> {
  const { data, error } = await rpc.rpc("marche_procurement_quote", { p: { lines: sanitizeLines(lines) } });
  if (error) fail(error);
  return data as ProcurementQuote;
}

export async function authorizeProcurement(args: {
  lines: ProcurementLineInput[];
  ceilingGnf: number;
  clientRequestId: string;
}): Promise<ProcurementRequest> {
  const { data, error } = await rpc.rpc("marche_procurement_authorize", {
    p: {
      lines: sanitizeLines(args.lines),
      ceiling_gnf: args.ceilingGnf,
      client_request_id: args.clientRequestId,
    },
  });
  if (error) fail(error);
  return data as ProcurementRequest;
}

export async function increaseProcurementCeiling(args: {
  requestId: string;
  newCeilingGnf: number;
  clientRequestId: string;
}): Promise<ProcurementRequest> {
  const { data, error } = await rpc.rpc("marche_procurement_increase", {
    p: {
      request_id: args.requestId,
      new_ceiling_gnf: args.newCeilingGnf,
      client_request_id: args.clientRequestId,
    },
  });
  if (error) fail(error);
  return data as ProcurementRequest;
}

export async function cancelProcurement(requestId: string, reason?: string): Promise<ProcurementRequest> {
  const { data, error } = await rpc.rpc("marche_procurement_cancel", {
    p_request_id: requestId,
    p_reason: reason ?? null,
  });
  if (error) fail(error);
  return data as ProcurementRequest;
}

export async function getProcurementRequest(requestId: string): Promise<ProcurementRequest | null> {
  const { data, error } = await rpc.rpc("marche_procurement_get", { p_request_id: requestId });
  if (error) fail(error);
  return (data as ProcurementRequest | null) ?? null;
}

export async function listProcurementRequests(limit = 20) {
  const { data, error } = await rpc.rpc("marche_procurement_list", { p_limit: limit });
  if (error) fail(error);
  return (data ?? []) as Pick<
    ProcurementRequest,
    "id" | "status" | "authorized_ceiling_gnf" | "actual_spend_gnf" | "line_count" | "estimate_status" | "client_request_id"
  >[];
}

/* ------------------------------------------------------------------ */
/* Durable request identity (idempotency)                              */
/* ------------------------------------------------------------------ */

const KEY_PREFIX = "chop.marche.procurement.key.";

/** Local fingerprint of a basket + ceiling. Mirrors what the server hashes. */
export function procurementIntentKey(lines: ProcurementLineInput[], ceilingGnf: number): string {
  const l = sanitizeLines(lines)
    .map((x) => `${x.commodity_code}/${x.variant_code}/${x.option_code}:${x.qty}`)
    .sort()
    .join(",");
  return `${l}|${ceilingGnf}`;
}

function storage(): Storage | null {
  try {
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    return null;
  }
}

export interface ProcurementRequestIdStore {
  /** Same uuid while the basket + ceiling are unchanged, so a retry replays instead of duplicating. */
  idFor(lines: ProcurementLineInput[], ceilingGnf: number): string;
  reset(lines?: ProcurementLineInput[], ceilingGnf?: number): void;
}

export function createProcurementRequestIdStore(scope = "default"): ProcurementRequestIdStore {
  const memory = new Map<string, string>();
  const slot = (k: string) => `${KEY_PREFIX}${scope}.${k}`;
  return {
    idFor(lines, ceilingGnf) {
      const k = procurementIntentKey(lines, ceilingGnf);
      const mem = memory.get(k);
      if (mem) return mem;
      const ls = storage();
      const persisted = ls?.getItem(slot(k)) ?? null;
      if (persisted) {
        memory.set(k, persisted);
        return persisted;
      }
      const id = newOrderRequestUuid();
      memory.set(k, id);
      try {
        ls?.setItem(slot(k), id);
      } catch {
        /* in-memory reuse still protects the session */
      }
      return id;
    },
    reset(lines, ceilingGnf) {
      const ls = storage();
      if (lines) {
        const k = procurementIntentKey(lines, ceilingGnf ?? 0);
        memory.delete(k);
        try {
          ls?.removeItem(slot(k));
        } catch {
          /* ignore */
        }
        return;
      }
      for (const k of memory.keys()) {
        try {
          ls?.removeItem(slot(k));
        } catch {
          /* ignore */
        }
      }
      memory.clear();
    },
  };
}

/* ------------------------------------------------------------------ */
/* Honest French copy                                                  */
/* ------------------------------------------------------------------ */

/** Never invents a price or certainty: explains WHY no estimate exists. */
export function insufficientDataMessageFr(quote: Pick<ProcurementQuote, "estimate_unavailable_reason" | "min_samples" | "observation_window_hours">): string {
  const min = quote.min_samples ?? null;
  const win = quote.observation_window_hours ?? null;
  const base = "Estimation indisponible : pas assez de relevés de prix récents pour ce panier.";
  if (min && win) {
    return `${base} Il faut au moins ${min} relevés sur les ${Math.round(win / 24)} derniers jours.`;
  }
  return base;
}

export function confidenceLabelFr(c: string | null | undefined): string | null {
  if (c === "high") return "Confiance élevée";
  if (c === "medium") return "Confiance moyenne";
  if (c === "low") return "Confiance faible";
  return null;
}

/** Machine-readable server refusals mapped to honest customer copy. */
export function procurementErrorFr(message: string): string {
  const m = (message || "").toUpperCase();
  if (m.includes("PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA"))
    return "Estimation indisponible : autorisation impossible pour l'instant.";
  if (m.includes("PROCUREMENT_CEILING_BELOW_ESTIMATE"))
    return "Le montant maximum doit être au moins égal à l'estimation.";
  if (m.includes("PROCUREMENT_CEILING_ABOVE_MAXIMUM")) return "Ce montant maximum dépasse la limite autorisée.";
  if (m.includes("PROCUREMENT_CEILING_NOT_MONOTONIC")) return "Le nouveau maximum doit être supérieur à l'actuel.";
  if (m.includes("PROCUREMENT_CEILING_INVALID")) return "Montant maximum invalide.";
  if (m.includes("IDEMPOTENCY_CONFLICT")) return "Le panier a changé. Recommencez l'autorisation.";
  if (m.includes("INSUFFICIENT_FUNDS") || m.includes("HOLD_FAILED"))
    return "Solde insuffisant pour bloquer ce montant maximum.";
  if (m.includes("PROCUREMENT_QTY_OUT_OF_RANGE") || m.includes("PROCUREMENT_QTY_NOT_STEP_ALIGNED"))
    return "Quantité non autorisée pour cette unité de vente.";
  if (m.includes("PROCUREMENT_AUTH_REQUIRED")) return "Connectez-vous pour autoriser un achat.";
  if (m.includes("PROCUREMENT_TOO_MANY_LINES")) return "Trop d'articles dans le panier.";
  if (m.includes("PROCUREMENT_EMPTY_BASKET")) return "Votre panier est vide.";
  return "Autorisation refusée par CHOP CHOP.";
}
