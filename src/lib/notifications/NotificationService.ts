/**
 * NotificationService — single client-side entry point for all outbound
 * notifications across CHOP CHOP. Delegates each channel to its dedicated
 * edge function:
 *
 *   • email     → send-transactional-email
 *   • sms       → send-message (SMS hint)
 *   • whatsapp  → send-message (WhatsApp hint)
 *   • inapp     → send-message (in-app)
 *   • push      → reserved for future provider
 *
 * Logs every attempt to public.notification_log via the backend (the edge
 * functions are responsible for writing their per-channel logs; this client
 * also writes a unified row for cross-channel observability).
 */
import { supabase } from "@/integrations/supabase/client";
import { MessageService } from "@/lib/messaging";
import type { MessageTemplate } from "@/lib/messaging/types";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export type NotificationChannel =
  | "email"
  | "sms"
  | "whatsapp"
  | "push"
  | "inapp";

export type NotificationPriority = "critical" | "high" | "normal" | "low";

export interface NotifyOptions {
  /** Logical template name (channel-specific keys allowed inside payload). */
  template: string;
  /** Priority influences channel routing and retry behaviour. */
  priority?: NotificationPriority;
  /** Recipient user id (for logging + preference lookup). */
  userId?: string | null;
  /** Channels to attempt, in order. First success wins unless `fanout` is true. */
  channels: NotificationChannel[];
  /** When true, send on every channel rather than stop at first success. */
  fanout?: boolean;
  /** Per-channel destinations. */
  to: {
    email?: string;
    phone?: string; // E.164
  };
  /** Per-channel template payloads. */
  payload?: {
    email?: { templateName: string; data: Record<string, unknown> };
    sms?: { template: MessageTemplate; vars?: Record<string, string | number> };
    whatsapp?: { template: MessageTemplate; vars?: Record<string, string | number> };
    inapp?: { template: MessageTemplate; vars?: Record<string, string | number> };
  };
}

export interface ChannelResult {
  channel: NotificationChannel;
  ok: boolean;
  id?: string;
  error?: string;
}

export interface NotifyResult {
  ok: boolean;
  attempts: ChannelResult[];
}

async function logAttempt(
  channel: NotificationChannel,
  template: string,
  status: "pending" | "sent" | "failed" | "suppressed" | "skipped",
  opts: {
    userId?: string | null;
    priority?: NotificationPriority;
    recipient?: string;
    externalId?: string;
    payload?: Record<string, unknown>;
    error?: string;
  },
) {
  try {
    await supabase.from("notification_log").insert({
      user_id: opts.userId ?? null,
      channel,
      template,
      status,
      priority: opts.priority ?? "normal",
      recipient: opts.recipient ?? null,
      external_id: opts.externalId ?? null,
      payload: (opts.payload ?? {}) as any,
      error_message: opts.error ?? null,
    });
  } catch {
    // never let logging break the send path
  }
  // Mirror to analytics for reliability dashboards.
  if (status === "sent" || status === "failed") {
    Analytics.track(
      status === "sent" ? "notification.sent" : "notification.failed",
      {
        metadata: {
          channel,
          template,
          priority: opts.priority ?? "normal",
          error: opts.error,
        },
      },
    );
  }
}

async function sendEmail(opts: NotifyOptions): Promise<ChannelResult> {
  const email = opts.to.email;
  const tpl = opts.payload?.email;
  if (!email || !tpl) {
    return { channel: "email", ok: false, error: "missing_email_recipient_or_template" };
  }
  const { data, error } = await supabase.functions.invoke(
    "send-transactional-email",
    {
      body: {
        templateName: tpl.templateName,
        recipientEmail: email,
        templateData: tpl.data,
      },
    },
  );
  if (error) {
    await logAttempt("email", opts.template, "failed", {
      userId: opts.userId,
      priority: opts.priority,
      recipient: email,
      payload: tpl.data,
      error: error.message,
    });
    return { channel: "email", ok: false, error: error.message };
  }
  await logAttempt("email", opts.template, "sent", {
    userId: opts.userId,
    priority: opts.priority,
    recipient: email,
    payload: tpl.data,
  });
  return { channel: "email", ok: true, id: (data as any)?.queued ? "queued" : undefined };
}

async function sendViaMessageService(
  channel: "sms" | "whatsapp" | "inapp",
  opts: NotifyOptions,
): Promise<ChannelResult> {
  const tpl =
    channel === "sms"
      ? opts.payload?.sms
      : channel === "whatsapp"
      ? opts.payload?.whatsapp
      : opts.payload?.inapp;
  const recipient = channel === "inapp" ? opts.userId ?? "" : opts.to.phone ?? "";

  if (!tpl || !recipient) {
    return { channel, ok: false, error: `missing_${channel}_recipient_or_template` };
  }

  const result = await MessageService.send({
    template: tpl.template,
    to: recipient,
    vars: tpl.vars,
    userId: opts.userId ?? undefined,
    channelHint: channel === "inapp" ? undefined : channel,
  });

  await logAttempt(channel, opts.template, result.ok ? "sent" : "failed", {
    userId: opts.userId,
    priority: opts.priority,
    recipient,
    payload: { vars: tpl.vars, template: tpl.template },
    externalId: result.id,
    error: result.error,
  });

  return { channel, ok: result.ok, id: result.id, error: result.error };
}

async function notify(opts: NotifyOptions): Promise<NotifyResult> {
  const attempts: ChannelResult[] = [];
  for (const channel of opts.channels) {
    let r: ChannelResult;
    if (channel === "email") r = await sendEmail(opts);
    else if (channel === "push") {
      r = { channel, ok: false, error: "push_provider_not_configured" };
      await logAttempt("push", opts.template, "skipped", {
        userId: opts.userId,
        priority: opts.priority,
        error: r.error,
      });
    } else r = await sendViaMessageService(channel, opts);
    attempts.push(r);
    if (r.ok && !opts.fanout) break;
  }
  return { ok: attempts.some((a) => a.ok), attempts };
}

/**
 * Deterministic priority routing: in-app → WhatsApp → SMS → email.
 *
 * Tries channels in this fixed order, stops at the first success, and
 * skips channels with no recipient/template (logged as `skipped`). SMS
 * is wired as a placeholder — it will be attempted only if a `sms`
 * payload is supplied; otherwise it is recorded as skipped to keep
 * downstream observability honest.
 *
 * Use this when you want fallback delivery without spamming every
 * channel at once.
 */
const PRIORITY_ORDER: NotificationChannel[] = ["inapp", "whatsapp", "sms", "email"];

async function notifyWithPriority(
  opts: Omit<NotifyOptions, "channels" | "fanout">,
): Promise<NotifyResult> {
  const attempts: ChannelResult[] = [];
  let inappFailedFirst = false;
  for (const channel of PRIORITY_ORDER) {
    const eligible = canAttempt(channel, opts as NotifyOptions);
    if ("reason" in eligible) {
      const reason = eligible.reason;
      await logAttempt(channel, opts.template, "skipped", {
        userId: opts.userId,
        priority: opts.priority,
        error: reason,
      });
      attempts.push({ channel, ok: false, error: reason });
      continue;
    }
    let r: ChannelResult;
    if (channel === "email") r = await sendEmail(opts as NotifyOptions);
    else r = await sendViaMessageService(
      channel as "inapp" | "whatsapp" | "sms",
      opts as NotifyOptions,
    );
    attempts.push(r);
    if (channel === "inapp" && !r.ok) inappFailedFirst = true;
    if (channel === "whatsapp" && r.ok && inappFailedFirst) {
      Analytics.track("whatsapp.fallback.used", {
        metadata: {
          template: opts.template,
          priority: opts.priority ?? "normal",
          reason: "inapp_failed",
        },
      });
    }
    if (r.ok) break; // deterministic stop on first delivered channel
  }
  return { ok: attempts.some((a) => a.ok), attempts };
}

function canAttempt(
  channel: NotificationChannel,
  opts: NotifyOptions,
): { ok: true } | { ok: false; reason: string } {
  if (channel === "push") return { ok: false, reason: "push_provider_not_configured" };
  if (channel === "inapp") {
    if (!opts.userId) return { ok: false, reason: "missing_user_id" };
    if (!opts.payload?.inapp) return { ok: false, reason: "missing_inapp_template" };
    return { ok: true };
  }
  if (channel === "whatsapp") {
    if (!opts.to.phone) return { ok: false, reason: "missing_phone" };
    if (!opts.payload?.whatsapp) return { ok: false, reason: "missing_whatsapp_template" };
    return { ok: true };
  }
  if (channel === "sms") {
    if (!opts.to.phone) return { ok: false, reason: "missing_phone" };
    if (!opts.payload?.sms) return { ok: false, reason: "sms_placeholder_not_configured" };
    return { ok: true };
  }
  if (channel === "email") {
    if (!opts.to.email) return { ok: false, reason: "missing_email" };
    if (!opts.payload?.email) return { ok: false, reason: "missing_email_template" };
    return { ok: true };
  }
  return { ok: false, reason: "unknown_channel" };
}

export const NotificationService = {
  notify,
  notifyWithPriority,

  // ---------- Convenience helpers (top 10 transactional flows) ----------

  welcome: (userId: string, email: string, firstName?: string) =>
    notify({
      template: "welcome",
      priority: "normal",
      userId,
      channels: ["email"],
      to: { email },
      payload: { email: { templateName: "welcome", data: { firstName } } },
    }),

  topupSuccess: (
    userId: string,
    contacts: { email?: string; phone?: string },
    data: {
      amountGnf: number;
      reference: string;
      agentName?: string;
      agentLocation?: string;
      newBalanceGnf?: number;
      firstName?: string;
    },
  ) =>
    notify({
      template: "topup_success",
      priority: "high",
      userId,
      channels: ["whatsapp", "sms", "email"],
      fanout: true,
      to: contacts,
      payload: {
        email: {
          templateName: "topup-success",
          data: { occurredAt: new Date().toISOString(), ...data },
        },
        whatsapp: {
          template: "topup_success",
          vars: { amount: data.amountGnf, ref: data.reference },
        },
        sms: {
          template: "topup_success",
          vars: { amount: data.amountGnf, ref: data.reference },
        },
      },
    }),

  paymentReceipt: (
    userId: string,
    contacts: { email?: string; phone?: string },
    data: {
      amountGnf: number;
      reference: string;
      merchantName?: string;
      paymentMethod?: string;
      firstName?: string;
    },
  ) =>
    notify({
      template: "payment_receipt",
      priority: "high",
      userId,
      channels: ["email", "whatsapp", "sms"],
      to: contacts,
      payload: {
        email: {
          templateName: "payment-receipt",
          data: { occurredAt: new Date().toISOString(), ...data },
        },
        whatsapp: {
          template: "payment_success",
          vars: { amount: data.amountGnf, ref: data.reference },
        },
        sms: {
          template: "payment_success",
          vars: { amount: data.amountGnf, ref: data.reference },
        },
      },
    }),

  refundProcessed: (
    userId: string,
    contacts: { email?: string; phone?: string },
    data: {
      amountGnf: number;
      reference: string;
      reason?: string;
      originalReference?: string;
      firstName?: string;
    },
  ) =>
    notify({
      template: "refund_processed",
      priority: "high",
      userId,
      channels: ["email", "whatsapp"],
      to: contacts,
      payload: {
        email: {
          templateName: "refund-processed",
          data: { occurredAt: new Date().toISOString(), ...data },
        },
        whatsapp: {
          template: "refund",
          vars: { amount: data.amountGnf, ref: data.reference },
        },
      },
    }),

  rideReceipt: (
    userId: string,
    contacts: { email?: string; phone?: string },
    data: {
      fareGnf: number;
      reference: string;
      mode?: "moto" | "toktok" | "voiture";
      driverName?: string;
      pickup?: string;
      destination?: string;
      durationMinutes?: number;
      distanceKm?: number;
      firstName?: string;
    },
  ) =>
    notify({
      template: "ride_receipt",
      priority: "high",
      userId,
      channels: ["email"],
      to: contacts,
      payload: {
        email: {
          templateName: "ride-receipt",
          data: { occurredAt: new Date().toISOString(), ...data },
        },
      },
    }),

  orderConfirmed: (
    userId: string,
    contacts: { email?: string; phone?: string },
    data: {
      totalGnf: number;
      reference: string;
      merchantName?: string;
      itemCount?: number;
      estimatedDelivery?: string;
      firstName?: string;
    },
  ) =>
    notify({
      template: "order_confirmed",
      priority: "high",
      userId,
      channels: ["email", "whatsapp"],
      to: contacts,
      payload: {
        email: {
          templateName: "order-confirmed",
          data: { occurredAt: new Date().toISOString(), ...data },
        },
      },
    }),

  orderDelivered: (
    userId: string,
    contacts: { email?: string; phone?: string },
    data: {
      reference: string;
      merchantName?: string;
      firstName?: string;
    },
  ) =>
    notify({
      template: "order_delivered",
      priority: "normal",
      userId,
      channels: ["email", "whatsapp"],
      to: contacts,
      payload: {
        email: {
          templateName: "order-delivered",
          data: { deliveredAt: new Date().toISOString(), ...data },
        },
        whatsapp: {
          template: "delivery_completed",
          vars: { ref: data.reference },
        },
      },
    }),

  driverApproved: (userId: string, email: string, firstName?: string, vehicleType?: string) =>
    notify({
      template: "driver_approved",
      priority: "high",
      userId,
      channels: ["email"],
      to: { email },
      payload: {
        email: {
          templateName: "driver-approved",
          data: { firstName, vehicleType },
        },
      },
    }),

  securityAlert: (
    userId: string,
    email: string,
    data: {
      eventType?: string;
      device?: string;
      location?: string;
      ipAddress?: string;
      firstName?: string;
    },
  ) =>
    notify({
      template: "security_alert",
      priority: "critical",
      userId,
      channels: ["email"],
      to: { email },
      payload: {
        email: {
          templateName: "security-alert",
          data: { occurredAt: new Date().toISOString(), ...data },
        },
      },
    }),

  otpFallback: (email: string, code: string, expiresInMinutes = 10) =>
    notify({
      template: "otp_fallback",
      priority: "critical",
      channels: ["email"],
      to: { email },
      payload: {
        email: {
          templateName: "otp-fallback",
          data: { code, expiresInMinutes },
        },
      },
    }),
};