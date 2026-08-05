import { supabase } from "@/integrations/supabase/client";

/**
 * Thin client for the `account-recovery` Edge Function.
 *
 * Everything secret (date of birth, answers, recovery key, passwords) is sent
 * straight to the server and never persisted in localStorage, sessionStorage,
 * the URL, analytics or the console.
 */

export const GENERIC_RECOVERY_FAILURE =
  "Informations de récupération incorrectes ou demande expirée.";

export interface RecoveryQuestionPrompt {
  id: string;
  label: string;
}

interface CallResult<T> {
  ok: boolean;
  message?: string;
  data?: T;
}

async function call<T>(payload: Record<string, unknown>): Promise<CallResult<T>> {
  try {
    const { data, error } = await supabase.functions.invoke("account-recovery", {
      body: payload,
    });
    if (error) {
      // Non-2xx responses still carry a JSON body with a generic message.
      const ctx = (error as { context?: Response }).context;
      if (ctx && typeof ctx.json === "function") {
        try {
          const parsed = (await ctx.json()) as { message?: string };
          return { ok: false, message: parsed?.message ?? GENERIC_RECOVERY_FAILURE };
        } catch {
          /* fall through */
        }
      }
      return { ok: false, message: "Connexion instable. Réessayez." };
    }
    const res = data as { ok?: boolean; message?: string };
    if (!res?.ok) return { ok: false, message: res?.message ?? GENERIC_RECOVERY_FAILURE };
    return { ok: true, data: data as T };
  } catch {
    // Offline / timeout must never look like a success.
    return { ok: false, message: "Connexion instable. Réessayez." };
  }
}

export interface EnrollResult {
  recovery_key: string;
  enrollment_token: string;
}

export function enrollRecovery(input: {
  birthdate: string;
  questions: { id: string; answer: string }[];
}) {
  return call<EnrollResult>({ action: "enroll", ...input });
}

export function rotateRecovery(input: {
  current_password: string;
  birthdate: string;
  questions: { id: string; answer: string }[];
}) {
  return call<EnrollResult>({ action: "rotate", ...input });
}

export function confirmRecoveryEnrollment(input: {
  enrollment_token: string;
  key_tail: string;
}) {
  return call<{ recovery_key_version: number }>({ action: "enroll_confirm", ...input });
}

export function changePasswordSelf(input: {
  current_password: string;
  new_password: string;
}) {
  return call<Record<string, never>>({ action: "change_password", ...input });
}

export interface StartResult {
  challenge_id: string;
  expires_at: string;
  questions: RecoveryQuestionPrompt[];
}

export function startRecovery(identifier: string) {
  return call<StartResult>({ action: "start", identifier });
}

export function verifyRecovery(input: {
  challenge_id: string;
  birthdate: string;
  answers: { id: string; answer: string }[];
  recovery_key: string;
}) {
  return call<{ reset_token: string; expires_in: number }>({ action: "verify", ...input });
}

export function resetPasswordWithRecovery(input: {
  challenge_id: string;
  reset_token: string;
  new_password: string;
}) {
  return call<{ recovery_key: string; sessions_revoked: boolean }>({
    action: "reset",
    ...input,
  });
}

export interface RecoveryStatus {
  configured: boolean;
  recovery_key_version?: number;
  setup_completed_at?: string | null;
  rotated_at?: string | null;
  question_ids: string[];
}

export async function fetchRecoveryStatus(): Promise<RecoveryStatus | null> {
  const { data, error } = await supabase.rpc("my_account_recovery_status");
  if (error || !data) return null;
  return data as unknown as RecoveryStatus;
}