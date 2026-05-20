import type { WalletTransaction } from "@/hooks/useWallet";

export type TxDirection = "in" | "out";

/**
 * Calm, ecosystem-aware label for a wallet transaction.
 * Picks human, French phrasing based on type + direction, with extra
 * heuristics on description / related_entity to recognise Repas, Marché,
 * courier earnings and merchant inflows. No fintech jargon.
 */
export function txLabel(tx: WalletTransaction, dir: TxDirection): string {
  const ctx = txContext(tx);
  const { isRepas, isMarche, isCourier, isCHOPPay, missionKind, isPeer } = ctx;

  switch (tx.type) {
    case "topup":
      return "Recharge reçue";
    case "payout":
      return "Versement reçu";
    case "refund":
      return dir === "in" ? "Remboursement reçu" : "Remboursement envoyé";
    case "commission":
      return "Commission CHOP";
    case "hold":
      return "Fonds réservés";
    case "release":
      return "Fonds libérés";
    case "adjustment":
      return "Ajustement";
    case "transfer":
      if (isPeer) return dir === "in" ? "Reçu d'un ami" : "Envoyé à un ami";
      return dir === "in" ? "Transfert reçu" : "Paiement envoyé";
    case "capture":
    case "payment": {
      if (dir === "in") {
        if (isCourier) {
          if (missionKind === "repas") return "Gain Livraison Repas reçu";
          if (missionKind === "marche") return "Gain Livraison Marché reçu";
          if (missionKind === "moto") return "Gain Course Moto reçu";
          if (missionKind === "envoyer") return "Gain Envoyer reçu";
          if (isRepas) return "Gain Livraison Repas reçu";
          if (isMarche) return "Gain Livraison Marché reçu";
          return "Gain mission reçu";
        }
        if (isRepas) return "Paiement Repas reçu";
        if (isMarche) return "Vente Marché reçue";
        if (isCHOPPay) return "Paiement CHOPPay reçu";
        return "Paiement reçu";
      }
      if (isRepas) return "Livraison Repas payée";
      if (isMarche) return "Achat Marché payé";
      if (isCHOPPay) return "Paiement CHOPPay";
      return "Paiement envoyé";
    }
    default:
      return dir === "in" ? "Crédit reçu" : "Débit envoyé";
  }
}

export function txStatusCopy(status: string): { label: string; tone: "pending" | "failed" | "cancelled" | "ok" } | null {
  switch (status) {
    case "pending":
      return { label: "En attente", tone: "pending" };
    case "failed":
      return { label: "Paiement échoué", tone: "failed" };
    case "cancelled":
      return { label: "Annulé", tone: "cancelled" };
    case "reversed":
      return { label: "Remboursé", tone: "cancelled" };
    default:
      return null;
  }
}

/**
 * Payout/availability copy used in the receipt sheet to reassure
 * couriers and merchants. Calm, plain-French; never banking jargon.
 */
export function payoutAvailabilityCopy(tx: WalletTransaction, dir: TxDirection): { label: string; tone: "ok" | "pending" | "muted" } {
  if (tx.status === "pending") return { label: "Paiement en cours de traitement", tone: "pending" };
  if (tx.status === "failed") return { label: "Paiement échoué", tone: "muted" };
  if (tx.status === "cancelled" || tx.status === "reversed") return { label: "Transaction annulée", tone: "muted" };
  if (dir === "in") {
    const { isCourier } = txContext(tx);
    if (isCourier) return { label: "Gain confirmé · disponible dans CHOPWallet", tone: "ok" };
    return { label: "Disponible dans CHOPWallet", tone: "ok" };
  }
  return { label: "Paiement confirmé", tone: "ok" };
}

export type MissionKind = "moto" | "repas" | "marche" | "envoyer" | null;

export interface TxContext {
  isRepas: boolean;
  isMarche: boolean;
  isCourier: boolean;
  isCHOPPay: boolean;
  isPeer: boolean;
  missionKind: MissionKind;
  pickupArea: string | null;
  dropoffArea: string | null;
  merchantName: string | null;
}

/**
 * Best-effort context extraction from description + related_entity.
 * Description heuristics: "… · Bambeto → Kaloum", "… · Resto X",
 * "mission:moto:…", "mission:repas:…". Safe defaults when unknown.
 */
export function txContext(tx: WalletTransaction): TxContext {
  const desc = (tx.description ?? "");
  const lower = desc.toLowerCase();
  const ref = (tx.related_entity ?? "").toLowerCase();

  const isRepas = /repas|food|menu|restaurant|plat/.test(lower) || ref.startsWith("food_") || ref.startsWith("repas:") || ref.includes(":repas:");
  const isMarche = /march[ée]|marketplace|listing|article|vente/.test(lower) || ref.startsWith("listing:") || ref.startsWith("marketplace") || ref.includes(":marche:");
  const isCourier = /coursier|livraison|gain|mission|course/.test(lower) || ref.startsWith("mission:");
  const isCHOPPay = /choppay|merchant|marchand/.test(lower);
  const isPeer = ref.startsWith("transfer:peer") || /ami|peer|p2p/.test(lower);

  let missionKind: MissionKind = null;
  if (ref.startsWith("mission:")) {
    const part = ref.split(":")[1] ?? "";
    if (part.startsWith("moto") || part === "ride") missionKind = "moto";
    else if (part.startsWith("repas") || part.startsWith("food")) missionKind = "repas";
    else if (part.startsWith("marche") || part.startsWith("marketplace")) missionKind = "marche";
    else if (part.startsWith("envoyer") || part.startsWith("courier")) missionKind = "envoyer";
  }
  if (!missionKind && isCourier) {
    if (/moto|course/.test(lower)) missionKind = "moto";
    else if (/repas|food|restaurant/.test(lower)) missionKind = "repas";
    else if (/march[ée]|marketplace|listing/.test(lower)) missionKind = "marche";
    else if (/envoyer|colis|coursier/.test(lower)) missionKind = "envoyer";
  }

  // Pickup → Dropoff parsing, e.g. "Mission · Bambeto → Kaloum".
  let pickupArea: string | null = null;
  let dropoffArea: string | null = null;
  const arrow = desc.match(/([A-ZÀ-Ý][\wÀ-ÿ' -]{1,30})\s*(?:→|->|–|-|à)\s*([A-ZÀ-Ý][\wÀ-ÿ' -]{1,30})/);
  if (arrow) {
    pickupArea = arrow[1].trim();
    dropoffArea = arrow[2].trim();
  }

  // Merchant name, e.g. "Paiement CHOPPay · Boutique X" or "Repas · Chez Mama".
  let merchantName: string | null = null;
  const sep = desc.split(/\s·\s|\s—\s|\s-\s/);
  if (sep.length > 1) {
    const candidate = sep[sep.length - 1].trim();
    if (candidate && !arrow) merchantName = candidate;
  }

  return { isRepas, isMarche, isCourier, isCHOPPay, isPeer, missionKind, pickupArea, dropoffArea, merchantName };
}

export const MISSION_KIND_LABEL: Record<Exclude<MissionKind, null>, string> = {
  moto: "Course Moto",
  repas: "Livraison Repas",
  marche: "Livraison Marché",
  envoyer: "Envoyer (Colis)",
};

export type TxGroupKey = "today" | "yesterday" | "this_week" | "this_month" | "older";

export const TX_GROUP_LABEL: Record<TxGroupKey, string> = {
  today: "Aujourd'hui",
  yesterday: "Hier",
  this_week: "Cette semaine",
  this_month: "Ce mois-ci",
  older: "Plus ancien",
};

export function groupKeyFor(iso: string, now = new Date()): TxGroupKey {
  const d = new Date(iso);
  const startOfDay = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const today = startOfDay(now);
  const yesterday = today - 86400000;
  const dayMs = startOfDay(d);
  if (dayMs === today) return "today";
  if (dayMs === yesterday) return "yesterday";
  // ISO-like week: last 7 days (excluding today/yesterday)
  if (today - dayMs <= 6 * 86400000) return "this_week";
  if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth()) return "this_month";
  return "older";
}

export function groupTransactions<T extends { created_at: string }>(txs: T[]): Array<{ key: TxGroupKey; label: string; items: T[] }> {
  const buckets = new Map<TxGroupKey, T[]>();
  const now = new Date();
  for (const tx of txs) {
    const k = groupKeyFor(tx.created_at, now);
    if (!buckets.has(k)) buckets.set(k, []);
    buckets.get(k)!.push(tx);
  }
  const order: TxGroupKey[] = ["today", "yesterday", "this_week", "this_month", "older"];
  return order
    .filter((k) => buckets.has(k))
    .map((k) => ({ key: k, label: TX_GROUP_LABEL[k], items: buckets.get(k)! }));
}