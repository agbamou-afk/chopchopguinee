/**
 * CHOP CHOP — SMS templates.
 * All messages target Guinean numbers (+224) and stay under 160 chars when possible.
 * These return plain strings; an SMS adapter (Twilio / local provider) actually sends.
 */
import { formatGNF } from "@/lib/format";

const SIGN = "CHOP CHOP";

export const smsTemplates = {
  otpCode: (code: string) =>
    `${SIGN}: votre code de vérification est ${code}. Ne le partagez avec personne. Valable 10 min.`,
  welcome: (firstName: string) =>
    `Bienvenue sur ${SIGN}, ${firstName} ! Votre compte est actif. Bonne route et bons repas !`,
  topupSuccess: (amount: number, ref: string) =>
    `${SIGN}: recharge de ${formatGNF(amount)} confirmée. Réf ${ref}. Merci !`,
  paymentSuccess: (amount: number, ref: string) =>
    `${SIGN}: paiement de ${formatGNF(amount)} effectué. Réf ${ref}.`,
  refund: (amount: number, ref: string) =>
    `${SIGN}: remboursement de ${formatGNF(amount)} crédité. Réf ${ref}.`,
  rideConfirmed: (mode: "moto" | "toktok", fare: number) =>
    `${SIGN}: votre course ${mode.toUpperCase()} est confirmée. Tarif estimé ${formatGNF(fare)}.`,
  driverAssigned: (driver: string, plate: string, eta: string) =>
    `${SIGN}: ${driver} (${plate}) arrive dans ${eta}. Bonne route !`,
  deliveryCompleted: (ref: string) =>
    `${SIGN}: votre livraison ${ref} est terminée. Merci d'avoir utilisé ${SIGN} !`,
  suspiciousActivity: () =>
    `${SIGN} ALERTE: activité inhabituelle sur votre compte. Si ce n'est pas vous, changez votre PIN immédiatement.`,
};

export type SmsKey = keyof typeof smsTemplates;

/**
 * Mock SMS sender — logs to console; replace with a real adapter (Twilio, Orange, etc.)
 * when an SMS provider is connected.
 */
export async function sendSms(to: string, body: string): Promise<{ ok: boolean }> {
  // eslint-disable-next-line no-console
  console.info(`[SMS → ${to}]`, body);
  return { ok: true };
}
