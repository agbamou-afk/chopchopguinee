import type { WalletTransaction } from "@/hooks/useWallet";

export type TxDirection = "in" | "out";

/**
 * Calm, ecosystem-aware label for a wallet transaction.
 * Picks human, French phrasing based on type + direction, with extra
 * heuristics on description / related_entity to recognise Repas, Marché,
 * courier earnings and merchant inflows. No fintech jargon.
 */
export function txLabel(tx: WalletTransaction, dir: TxDirection): string {
  const desc = (tx.description ?? "").toLowerCase();
  const ref = (tx.related_entity ?? "").toLowerCase();

  const isRepas = /repas|food|menu|restaurant|plat/.test(desc) || ref.startsWith("food_") || ref.startsWith("repas:");
  const isMarche = /march[ée]|marketplace|listing|article|vente/.test(desc) || ref.startsWith("listing:") || ref.startsWith("marketplace");
  const isCourier = /coursier|livraison|gain|mission|course/.test(desc) || ref.startsWith("mission:");
  const isCHOPPay = /choppay|merchant|marchand/.test(desc);

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
      return dir === "in" ? "Transfert reçu" : "Paiement envoyé";
    case "capture":
    case "payment": {
      if (dir === "in") {
        if (isCourier) {
          if (isRepas) return "Gain livraison Repas reçu";
          if (isMarche) return "Gain livraison Marché reçu";
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