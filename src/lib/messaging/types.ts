/**
 * CHOP CHOP — messaging shared types.
 * Channels and templates are mirrored in the `send-message` edge function and
 * in the database enums (public.message_channel / public.message_template).
 */
export type MessageChannel = "whatsapp" | "sms" | "inapp";

export type MessageStatus =
  | "queued"
  | "sending"
  | "sent"
  | "delivered"
  | "read"
  | "failed";

export type MessageTemplate =
  | "otp_code"
  | "welcome"
  | "topup_pending"
  | "topup_success"
  | "payment_success"
  | "refund"
  | "ride_confirmed"
  | "driver_assigned"
  | "delivery_completed"
  | "suspicious_activity";

export interface SendOptions {
  template: MessageTemplate;
  to: string;                              // E.164, e.g. +224621234567
  vars?: Record<string, string | number>;
  userId?: string | null;
  channelHint?: Exclude<MessageChannel, "inapp">;
  maxRetries?: number;
}

export interface SendResult {
  ok: boolean;
  channel?: MessageChannel;
  provider?: string;
  id?: string;
  error?: string;
}

export interface NotificationPreferences {
  whatsapp_enabled: boolean;
  sms_enabled: boolean;
  topic_otp: boolean;
  topic_wallet: boolean;
  topic_ride: boolean;
  topic_marketing: boolean;
  preferred_channel: Exclude<MessageChannel, "inapp">;
}

export const defaultPreferences: NotificationPreferences = {
  whatsapp_enabled: true,
  sms_enabled: true,
  topic_otp: true,
  topic_wallet: true,
  topic_ride: true,
  topic_marketing: false,
  preferred_channel: "whatsapp",
};
