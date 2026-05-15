/**
 * walletNotifier — single-source dispatch for wallet lifecycle events.
 *
 * Guarantees that for any given wallet event (identified by an `eventId`)
 * the user gets:
 *   • exactly one toast
 *   • exactly one in-app notification row
 *   • at most one outbound WhatsApp / email queued
 *
 * Dedup uses sessionStorage so a re-mount, a duplicated realtime payload
 * or a manual page refresh after a credited topup won't re-fire.
 */
import { toast } from "sonner";
import { notifications } from "@/lib/notifications";
import { NotificationService } from "@/lib/notifications/NotificationService";
import { formatGNF } from "@/lib/format";

export type WalletEvent =
  | "topup_created"
  | "topup_credited"
  | "refund_processed"
  | "wallet_frozen"
  | "payout_sent";

export interface WalletEventPayload {
  /**
   * Stable per-occurrence id (e.g. `topup:<id>:credited`). Used for dedup.
   * If two callers fire the same `eventId`, only the first runs.
   */
  eventId: string;
  event: WalletEvent;
  amountGnf?: number;
  reference?: string;
  reason?: string;
  userId?: string | null;
  /** Recipient for WhatsApp / SMS (E.164). Skip channel if missing. */
  phone?: string;
  /** Recipient for email. Skip channel if missing. */
  email?: string;
  /** When false, skip queuing WhatsApp/email (e.g. silent admin events). */
  externalChannels?: boolean;
}

const DEDUP_KEY = "chopchop:wallet-events:seen";
const MAX_SEEN = 200;

function seenSet(): Set<string> {
  try {
    const raw = sessionStorage.getItem(DEDUP_KEY);
    return new Set(raw ? (JSON.parse(raw) as string[]) : []);
  } catch {
    return new Set();
  }
}

function markSeen(id: string) {
  try {
    const set = seenSet();
    set.add(id);
    const arr = Array.from(set).slice(-MAX_SEEN);
    sessionStorage.setItem(DEDUP_KEY, JSON.stringify(arr));
  } catch {}
}

function copy(p: WalletEventPayload): { title: string; body: string; tone: "success" | "error" | "info" } {
  const amount = p.amountGnf != null ? formatGNF(p.amountGnf) : "";
  const ref = p.reference ? ` (${p.reference})` : "";
  switch (p.event) {
    case "topup_created":
      return {
        title: "Recharge initiée",
        body: `Votre recharge${amount ? ` de ${amount}` : ""}${ref} a été créée.`,
        tone: "info",
      };
    case "topup_credited":
      return {
        title: "Recharge créditée",
        body: `${amount ? `${amount} ` : ""}ajoutés à votre portefeuille${ref}.`,
        tone: "success",
      };
    case "refund_processed":
      return {
        title: "Remboursement effectué",
        body: `Remboursement${amount ? ` de ${amount}` : ""}${ref} reçu sur votre portefeuille.`,
        tone: "success",
      };
    case "wallet_frozen":
      return {
        title: "CHOPWallet gelé",
        body: p.reason
          ? `Votre portefeuille a été gelé : ${p.reason}.`
          : "Votre portefeuille a été gelé. Contactez le support.",
        tone: "error",
      };
    case "payout_sent":
      return {
        title: "Virement envoyé",
        body: `Votre virement${amount ? ` de ${amount}` : ""}${ref} a été envoyé.`,
        tone: "success",
      };
  }
}

function fireToast(t: ReturnType<typeof copy>) {
  if (t.tone === "success") toast.success(t.title, { description: t.body });
  else if (t.tone === "error") toast.error(t.title, { description: t.body });
  else toast(t.title, { description: t.body });
}

async function queueExternal(p: WalletEventPayload, c: ReturnType<typeof copy>) {
  if (p.externalChannels === false) return;
  if (!p.phone && !p.email) return;
  // Only events that should reach the user out-of-app.
  const external: WalletEvent[] = ["topup_credited", "refund_processed", "wallet_frozen", "payout_sent"];
  if (!external.includes(p.event)) return;
  try {
    await NotificationService.notify({
      template: `wallet.${p.event}`,
      priority: p.event === "wallet_frozen" ? "critical" : "high",
      userId: p.userId ?? null,
      channels: [p.email ? "email" : null, p.phone ? "whatsapp" : null].filter(
        Boolean,
      ) as ("email" | "whatsapp")[],
      fanout: true,
      to: { email: p.email, phone: p.phone },
      payload: {
        email: {
          templateName: `wallet-${p.event.replace(/_/g, "-")}`,
          data: {
            title: c.title,
            body: c.body,
            amount_gnf: p.amountGnf ?? null,
            reference: p.reference ?? null,
          },
        },
      },
    });
  } catch {
    // queueing failure shouldn't break the in-app flow
  }
}

/**
 * Fire the full notification sequence exactly once per `eventId`.
 * Returns `true` if it ran, `false` if dedup'd.
 */
export async function notifyWalletEvent(p: WalletEventPayload): Promise<boolean> {
  if (!p.eventId) return false;
  const set = seenSet();
  if (set.has(p.eventId)) return false;
  markSeen(p.eventId);

  const c = copy(p);
  fireToast(c);
  notifications.push({ kind: "wallet", title: c.title, body: c.body });
  void queueExternal(p, c);
  return true;
}

/** Test / admin helper. */
export function _resetWalletDedup() {
  try { sessionStorage.removeItem(DEDUP_KEY); } catch {}
}