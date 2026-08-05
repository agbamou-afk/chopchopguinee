/**
 * Controlled recovery-question set.
 *
 * Every prompt asks for something the user *invents* for CHOPCHOP. No prompt
 * may reference a publicly discoverable fact (mother's maiden name, school,
 * hometown, birthday, favourite team, spouse, child, employer...). Keep this
 * list byte-identical with `src/lib/recovery/questions.ts`.
 */
export const RECOVERY_QUESTIONS: ReadonlyArray<{ id: string; label: string }> = [
  { id: "secret_word", label: "Quel mot secret avez-vous choisi uniquement pour CHOPCHOP ?" },
  { id: "fictional_place", label: "Quel nom fictif avez-vous donné à votre lieu préféré ?" },
  { id: "personal_phrase", label: "Quelle phrase personnelle avez-vous créée pour votre compte ?" },
  { id: "invented_nickname", label: "Quel surnom inventé n'utilisez-vous nulle part ailleurs ?" },
  { id: "imaginary_object", label: "Quel objet imaginaire avez-vous choisi comme souvenir secret ?" },
  { id: "invented_travel_word", label: "Quel mot inventé associez-vous à votre premier voyage idéal ?" },
];

export const QUESTION_IDS: ReadonlySet<string> = new Set(
  RECOVERY_QUESTIONS.map((q) => q.id),
);

export function questionLabel(id: string): string {
  return RECOVERY_QUESTIONS.find((q) => q.id === id)?.label ?? "";
}