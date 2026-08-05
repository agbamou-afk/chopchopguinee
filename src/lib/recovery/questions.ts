/**
 * Controlled recovery-question set (client mirror).
 *
 * Every prompt asks the user to *invent* something for CHOPCHOP only. No
 * prompt may reference a publicly discoverable fact (mother's maiden name,
 * school, hometown, birthday, favourite team, spouse, child, employer...).
 * Keep byte-identical with `supabase/functions/account-recovery/questions.ts`.
 */
export interface RecoveryQuestion {
  id: string;
  label: string;
}

export const RECOVERY_QUESTIONS: ReadonlyArray<RecoveryQuestion> = [
  { id: "secret_word", label: "Quel mot secret avez-vous choisi uniquement pour CHOPCHOP ?" },
  { id: "fictional_place", label: "Quel nom fictif avez-vous donné à votre lieu préféré ?" },
  { id: "personal_phrase", label: "Quelle phrase personnelle avez-vous créée pour votre compte ?" },
  { id: "invented_nickname", label: "Quel surnom inventé n'utilisez-vous nulle part ailleurs ?" },
  { id: "imaginary_object", label: "Quel objet imaginaire avez-vous choisi comme souvenir secret ?" },
  { id: "invented_travel_word", label: "Quel mot inventé associez-vous à votre premier voyage idéal ?" },
];

export const MIN_ANSWER_LENGTH = 3;
export const MIN_PASSWORD_LENGTH = 8;

export function questionLabel(id: string): string {
  return RECOVERY_QUESTIONS.find((q) => q.id === id)?.label ?? id;
}

/** Mirror of the server normalization, used only for local duplicate checks. */
export function normalizeAnswerLocal(raw: string): string {
  return raw
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}