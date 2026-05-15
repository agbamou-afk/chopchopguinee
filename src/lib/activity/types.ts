/**
 * CHOP CHOP — Unified ecosystem activity model.
 *
 * The timeline is NOT a social feed. It is operational history: rides,
 * CHOPPay merchant payments, CHOPWallet recharges, transfers, future Repas
 * & Marché orders. Every surface that talks about "history" should consume
 * `ActivityItem` so the ecosystem feels like one continuous log.
 */

export type ActivityKind =
  | "ride"
  | "merchant_payment"
  | "topup"
  | "transfer_in"
  | "transfer_out"
  | "refund"
  | "payout"
  | "food_order"
  | "market_order"
  | "support";

export type ActivityStatus = "completed" | "pending" | "failed" | "cancelled" | "in_progress";

export interface ActivityItem {
  id: string;
  kind: ActivityKind;
  /** Concise headline — e.g. "Course CHOP CHOP". */
  title: string;
  /** One-line context — e.g. "Kaloum → Ratoma" or merchant name. */
  subtitle?: string;
  /** Signed amount in GNF. Positive = money in, negative = money out. */
  amount?: number;
  status: ActivityStatus;
  /** ISO timestamp. */
  occurredAt: string;
  /** Stable reference for deep-link / receipt lookup. */
  reference?: string;
  /** Foreign entity (merchant id, ride id, etc.) for receipt expansion. */
  entityId?: string;
  /** Optional badge — verified merchant, CHOPPay seal, live ride. */
  badge?: "choppay" | "verified" | "live";
  /** Free-form metadata for the detail sheet (avoids re-querying). */
  meta?: Record<string, unknown>;
}

export type ActivityGroupKey = "today" | "yesterday" | "week" | "month" | "earlier";

export interface ActivityGroup {
  key: ActivityGroupKey;
  label: string;
  items: ActivityItem[];
}

const startOfDay = (d: Date) => {
  const c = new Date(d);
  c.setHours(0, 0, 0, 0);
  return c;
};

export function groupActivities(items: ActivityItem[]): ActivityGroup[] {
  const now = new Date();
  const today = startOfDay(now).getTime();
  const yesterday = today - 24 * 3600_000;
  const weekStart = today - 7 * 24 * 3600_000;
  const monthStart = today - 30 * 24 * 3600_000;

  const buckets: Record<ActivityGroupKey, ActivityItem[]> = {
    today: [],
    yesterday: [],
    week: [],
    month: [],
    earlier: [],
  };

  for (const it of items) {
    const t = new Date(it.occurredAt).getTime();
    if (t >= today) buckets.today.push(it);
    else if (t >= yesterday) buckets.yesterday.push(it);
    else if (t >= weekStart) buckets.week.push(it);
    else if (t >= monthStart) buckets.month.push(it);
    else buckets.earlier.push(it);
  }

  const labels: Record<ActivityGroupKey, string> = {
    today: "Aujourd'hui",
    yesterday: "Hier",
    week: "Cette semaine",
    month: "Ce mois-ci",
    earlier: "Plus tôt",
  };

  return (Object.keys(buckets) as ActivityGroupKey[])
    .filter((k) => buckets[k].length > 0)
    .map((k) => ({ key: k, label: labels[k], items: buckets[k] }));
}

export function formatActivityTime(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const time = d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
  if (sameDay) return time;
  const date = d.toLocaleDateString("fr-FR", { day: "2-digit", month: "short" });
  return `${date} · ${time}`;
}