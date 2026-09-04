import { useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PasswordInput } from "@/components/ui/password-input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import {
  RecoveryAnswerDraft,
  RecoveryQuestionsForm,
  validateRecoveryDraft,
} from "./RecoveryQuestionsForm";
import { RecoveryKeyCard } from "./RecoveryKeyCard";
import { confirmRecoveryEnrollment, enrollRecovery, rotateRecovery } from "@/lib/recovery/api";

const EMPTY: RecoveryAnswerDraft[] = [
  { id: "", answer: "" },
  { id: "", answer: "" },
  { id: "", answer: "" },
];

/**
 * Two-step recovery enrollment / rotation for a signed-in user.
 *
 * Step 1 collects DOB + 3 private questions (plus the current password when
 * rotating). Step 2 shows the server-generated key once and requires the user
 * to confirm they saved it before anything is persisted.
 */
export function RecoverySetupWizard({
  mode,
  onComplete,
}: {
  mode: "enroll" | "rotate";
  onComplete: () => void;
}) {
  const [step, setStep] = useState<1 | 2>(1);
  const [busy, setBusy] = useState(false);
  const [birthdate, setBirthdate] = useState("");
  const [drafts, setDrafts] = useState<RecoveryAnswerDraft[]>(EMPTY);
  const [currentPassword, setCurrentPassword] = useState("");
  const [recoveryKey, setRecoveryKey] = useState("");
  const [enrollmentToken, setEnrollmentToken] = useState("");

  const submitStep1 = async (e: React.FormEvent) => {
    e.preventDefault();
    const err = validateRecoveryDraft(birthdate, drafts);
    if (err) {
      toast({ title: "Vérifiez vos informations", description: err });
      return;
    }
    if (mode === "rotate" && currentPassword.length < 6) {
      toast({ title: "Mot de passe requis", description: "Entrez votre mot de passe actuel." });
      return;
    }
    setBusy(true);
    const payload = { birthdate, questions: drafts };
    const res =
      mode === "rotate"
        ? await rotateRecovery({ current_password: currentPassword, ...payload })
        : await enrollRecovery(payload);
    setBusy(false);
    if (!res.ok || !res.data) {
      toast({ title: "Échec", description: res.message ?? "Réessayez." });
      return;
    }
    setCurrentPassword("");
    setRecoveryKey(res.data.recovery_key);
    setEnrollmentToken(res.data.enrollment_token);
    setStep(2);
  };

  const confirmKey = async (tail: string) => {
    setBusy(true);
    const res = await confirmRecoveryEnrollment({ enrollment_token: enrollmentToken, key_tail: tail });
    setBusy(false);
    if (!res.ok) {
      toast({ title: "Confirmation impossible", description: res.message ?? "Réessayez." });
      return;
    }
    // Wipe every secret from memory as soon as it is no longer needed.
    setRecoveryKey("");
    setEnrollmentToken("");
    setDrafts(EMPTY);
    setBirthdate("");
    toast({
      title: "Récupération configurée",
      description: "Votre compte est protégé. Gardez votre clé en lieu sûr.",
    });
    onComplete();
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2" aria-label={`Étape ${step} sur 2`}>
        {[1, 2].map((s) => (
          <span
            key={s}
            className={`h-1.5 flex-1 rounded-full ${s <= step ? "bg-primary" : "bg-muted"}`}
          />
        ))}
      </div>

      {step === 1 ? (
        <form onSubmit={submitStep1} className="space-y-4">
          {mode === "rotate" && (
            <div>
              <Label htmlFor="reauth-password">Mot de passe actuel</Label>
              <PasswordInput
                id="reauth-password"
                autoComplete="current-password"
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                required
              />
            </div>
          )}
          <RecoveryQuestionsForm
            birthdate={birthdate}
            onBirthdateChange={setBirthdate}
            drafts={drafts}
            onDraftsChange={setDrafts}
          />
          <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
            {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Continuer"}
          </Button>
        </form>
      ) : (
        <RecoveryKeyCard
          recoveryKey={recoveryKey}
          busy={busy}
          onConfirm={confirmKey}
          confirmLabel={mode === "rotate" ? "Enregistrer la nouvelle clé" : "Terminer"}
        />
      )}
    </div>
  );
}