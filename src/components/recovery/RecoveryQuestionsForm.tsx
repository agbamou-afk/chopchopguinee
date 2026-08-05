import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  MIN_ANSWER_LENGTH,
  RECOVERY_QUESTIONS,
  normalizeAnswerLocal,
} from "@/lib/recovery/questions";

export interface RecoveryAnswerDraft {
  id: string;
  answer: string;
}

/** Client-side mirror of the server validation. The server remains authoritative. */
export function validateRecoveryDraft(
  birthdate: string,
  drafts: RecoveryAnswerDraft[],
): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthdate)) return "Indiquez votre date de naissance.";
  const year = Number(birthdate.slice(0, 4));
  if (year < 1900 || Date.parse(`${birthdate}T00:00:00Z`) > Date.now()) {
    return "Date de naissance invalide.";
  }
  if (drafts.length !== 3 || drafts.some((d) => !d.id)) return "Choisissez 3 questions.";
  if (new Set(drafts.map((d) => d.id)).size !== 3) return "Choisissez 3 questions différentes.";
  const normalized = drafts.map((d) => normalizeAnswerLocal(d.answer));
  if (normalized.some((a) => a.length < MIN_ANSWER_LENGTH)) {
    return `Chaque réponse doit contenir au moins ${MIN_ANSWER_LENGTH} caractères.`;
  }
  if (new Set(normalized).size === 1) return "Utilisez trois réponses différentes.";
  return null;
}

/**
 * Date of birth + three private questions/answers.
 *
 * Answers may be entirely invented — that is the point. All fields use
 * `autoComplete="off"` and `type="text"` so password managers never offer to
 * store an answer as a password.
 */
export function RecoveryQuestionsForm({
  birthdate,
  onBirthdateChange,
  drafts,
  onDraftsChange,
}: {
  birthdate: string;
  onBirthdateChange: (v: string) => void;
  drafts: RecoveryAnswerDraft[];
  onDraftsChange: (v: RecoveryAnswerDraft[]) => void;
}) {
  const setAt = (i: number, patch: Partial<RecoveryAnswerDraft>) => {
    onDraftsChange(drafts.map((d, idx) => (idx === i ? { ...d, ...patch } : d)));
  };

  return (
    <div className="space-y-4">
      <div>
        <Label htmlFor="recovery-dob">Date de naissance</Label>
        <Input
          id="recovery-dob"
          type="date"
          value={birthdate}
          onChange={(e) => onBirthdateChange(e.target.value)}
          autoComplete="off"
          max={new Date().toISOString().slice(0, 10)}
          required
        />
      </div>

      <p className="text-[12px] text-muted-foreground leading-snug">
        Choisissez 3 questions et inventez vos réponses. Elles{" "}
        <strong className="text-foreground">n'ont pas besoin d'être vraies</strong> : le plus sûr
        est même d'inventer. Ne choisissez rien que votre famille ou vos amis pourraient deviner.
      </p>

      {drafts.map((d, i) => {
        const taken = new Set(drafts.filter((_, idx) => idx !== i).map((x) => x.id));
        return (
          <div key={i} className="rounded-2xl border border-border p-3 space-y-2">
            <Label htmlFor={`recovery-q-${i}`} className="text-xs text-muted-foreground">
              Question {i + 1}
            </Label>
            <select
              id={`recovery-q-${i}`}
              value={d.id}
              onChange={(e) => setAt(i, { id: e.target.value })}
              className="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground"
            >
              <option value="">— Choisir une question —</option>
              {RECOVERY_QUESTIONS.filter((q) => !taken.has(q.id)).map((q) => (
                <option key={q.id} value={q.id}>
                  {q.label}
                </option>
              ))}
            </select>
            <Input
              aria-label={`Réponse à la question ${i + 1}`}
              type="text"
              value={d.answer}
              onChange={(e) => setAt(i, { answer: e.target.value })}
              placeholder="Votre réponse secrète"
              autoComplete="off"
              autoCorrect="off"
              spellCheck={false}
              data-1p-ignore
              data-lpignore="true"
              maxLength={120}
            />
          </div>
        );
      })}
    </div>
  );
}