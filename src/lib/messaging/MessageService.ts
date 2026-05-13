/**
 * MessageService — single client-side entry point for outbound messages.
 * Delegates the actual sending (provider selection, retry, fallback, logging)
 * to the `send-message` edge function so secrets stay server-side.
 *
 * Usage:
 *   import { MessageService } from "@/lib/messaging";
 *   await MessageService.send({
 *     template: "topup_success",
 *     to: "+224621234567",
 *     vars: { amount: 50000, ref: "CC-TX-XYZ" },
 *     userId: user.id,
 *   });
 */
import { supabase } from "@/integrations/supabase/client";
import type { SendOptions, SendResult } from "./types";

async function send(options: SendOptions): Promise<SendResult> {
  const { data, error } = await supabase.functions.invoke("send-message", {
    body: options,
  });
  if (error) {
    // eslint-disable-next-line no-console
    console.error("MessageService.send failed", error);
    return { ok: false, error: error.message };
  }
  return (data ?? { ok: false, error: "no response" }) as SendResult;
}

export const MessageService = {
  send,
  /** Convenience helpers — keep call sites short and template names central. */
  otp: (to: string, code: string, userId?: string) =>
    send({ template: "otp_code", to, vars: { code }, userId, channelHint: "sms", maxRetries: 2 }),
  topupPending: (to: string, amount: number, ref: string, code: string, userId?: string) =>
    send({ template: "topup_pending", to, vars: { amount, ref, code }, userId }),
  topupSuccess: (to: string, amount: number, ref: string, userId?: string) =>
    send({ template: "topup_success", to, vars: { amount, ref }, userId }),
  paymentSuccess: (to: string, amount: number, ref: string, userId?: string) =>
    send({ template: "payment_success", to, vars: { amount, ref }, userId }),
  refund: (to: string, amount: number, ref: string, userId?: string) =>
    send({ template: "refund", to, vars: { amount, ref }, userId }),
  rideConfirmed: (to: string, mode: "moto" | "toktok", fare: number, userId?: string) =>
    send({ template: "ride_confirmed", to, vars: { mode, fare }, userId }),
  driverAssigned: (to: string, driver: string, plate: string, eta: string, userId?: string) =>
    send({ template: "driver_assigned", to, vars: { driver, plate, eta }, userId }),
  deliveryCompleted: (to: string, ref: string, userId?: string) =>
    send({ template: "delivery_completed", to, vars: { ref }, userId }),
  suspiciousActivity: (to: string, userId?: string) =>
    send({ template: "suspicious_activity", to, userId, maxRetries: 2 }),
};
