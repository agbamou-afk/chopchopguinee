import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { Loader2, ShieldQuestion } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Seo } from "@/components/Seo";
import { RecoveryKeyCard } from "@/components/recovery/RecoveryKeyCard";
import { MIN_PASSWORD_LENGTH } from "@/lib/recovery/questions";
import {
  RecoveryQuestionPrompt,
  resetPasswordWithRecovery,
  startRecovery,
  verifyRecovery,
} from "@/lib/recovery/api";

type Step = "identify" | "challenge" | "password" | "newkey";

/**
 * Self-service password recovery — no admin, no email link, no OTP.
 *
 * Nothing sensitive is ever placed in the URL, localStorage or sessionStorage;
 * the challenge id and reset token live in React state for the tab's lifetime.
 */
export default function ForgotPassword() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const nextParam = params.get("next");
  const safeNext = nextParam && nextParam.startsWith("/") ? nextParam : null;

  const [step, setStep] = useState<Step>("identify");
  const [busy, setBusy] = useState(false);
  const [identifier, setIdentifier] = useState("");
  const [challengeId, setChallengeId] = useState("");
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [questions, setQuestions] = useState<RecoveryQuestionPrompt[]>([]);
  const [birthdate, setBirthdate] = useState("");
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [recoveryKey, setRecoveryKey] = useState("");
  const [resetToken, setResetToken] = useState("");
  const [password, setPassword] = useState("");
  const [password2, setPassword2] = useState("");
  const [newKey, setNewKey] = useState("");

  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  const remaining = useMemo(() => {
    if (!expiresAt) return null;
    const ms = Date.parse(expiresAt) - now;
    if (ms <= 0) return "00:00";
    const m = Math.floor(ms / 60000);
    const s = Math.floor((ms % 60000) / 1000);
    return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  }, [expiresAt, now]);

  const submitIdentify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (identifier.trim().length < 5) {
      toast({ title: "Information requise", description: "Entrez votre email ou votre numéro." });
      return;
    }
    setBusy(true);
    const res = await startRecovery(identifier.trim());
    setBusy(false);
    if (!res.ok || !res.data) {
      toast({ title: "Récupération", description: res.message ?? "Réessayez." });
      return;
    }
    setChallengeId(res.data.challenge_id);
    setExpiresAt(res.data.expires_at);
    setQuestions(res.data.questions);
    setAnswers({});
    setStep("challenge");
  };

  const submitChallenge = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    const res = await verifyRecovery({
      challenge_id: challengeId,
      birthdate,
      recovery_key: recoveryKey,
      answers: questions.map((q) => ({ id: q.id, answer: answers[q.id] ?? "" })),
    });
    setBusy(false);
    if (!res.ok || !res.data) {
      toast({ title: "Échec de la vérification", description: res.message });
      return;
    }
    // Secrets are wiped as soon as the server has accepted them.
    setBirthdate("");
    setAnswers({});
    setRecoveryKey("");
    setResetToken(res.data.reset_token);
    setStep("password");
  };

  const submitPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < MIN_PASSWORD_LENGTH) {
      toast({
        title: "Mot de passe trop court",
        description: `Utilisez au moins ${MIN_PASSWORD_LENGTH} caractères.`,
      });
      return;
    }
    if (password !== password2) {
      toast({ title: "Confirmation", description: "Les deux mots de passe ne correspondent pas." });
      return;
    }
    setBusy(true);
    const res = await resetPasswordWithRecovery({
      challenge_id: challengeId,
      reset_token: resetToken,
      new_password: password,
    });
    setBusy(false);
    if (!res.ok || !res.data) {
      toast({ title: "Échec", description: res.message });
      return;
    }
    setPassword("");
    setPassword2("");
    setResetToken("");
    setNewKey(res.data.recovery_key);
    setStep("newkey");
  };

  const stepIndex = { identify: 1, challenge: 2, password: 3, newkey: 4 }[step];

  return (
    <div className="min-h-screen bg-background px-4 py-8 flex justify-center">
      <Seo
        title="Mot de passe oublié — CHOPCHOP"
        description="Réinitialisez vous-même votre mot de passe CHOPCHOP avec votre date de naissance, vos questions privées et votre clé de récupération."
        canonical="/recovery"
      />
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-5">
          <BrandLogo size="lg" className="mb-2" />
          <h1 className="text-lg font-bold text-foreground">Mot de passe oublié</h1>
        </div>

        <div className="flex items-center gap-2 mb-4" aria-label={`Étape ${stepIndex} sur 4`}>
          {[1, 2, 3, 4].map((s) => (
            <span
              key={s}
              className={`h-1.5 flex-1 rounded-full ${s <= stepIndex ? "bg-primary" : "bg-muted"}`}
            />
          ))}
        </div>

        <div className="bg-card rounded-3xl shadow-elevated p-5">
          {step === "identify" && (
            <form onSubmit={submitIdentify} className="space-y-4">
              <div className="flex items-start gap-2 rounded-2xl bg-muted/50 border border-border p-3">
                <ShieldQuestion className="w-5 h-5 text-primary shrink-0 mt-0.5" aria-hidden />
                <p className="text-[12px] text-muted-foreground leading-snug">
                  Aucun email ni SMS n'est envoyé. Vous aurez besoin de votre date de naissance, de
                  vos réponses secrètes et de votre clé de récupération CHOPCHOP.
                </p>
              </div>
              <div>
                <Label htmlFor="identifier">Email ou numéro de téléphone</Label>
                <Input
                  id="identifier"
                  value={identifier}
                  onChange={(e) => setIdentifier(e.target.value)}
                  autoComplete="username"
                  placeholder="vous@exemple.com ou 6XX XX XX XX"
                  required
                />
              </div>
              <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
                {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Continuer"}
              </Button>
            </form>
          )}

          {step === "challenge" && (
            <form onSubmit={submitChallenge} className="space-y-4">
              <p className="text-[12px] text-muted-foreground" role="status">
                Répondez à ces 2 questions. Demande valable encore {remaining}.
              </p>
              <div>
                <Label htmlFor="dob">Date de naissance</Label>
                <Input
                  id="dob"
                  type="date"
                  value={birthdate}
                  onChange={(e) => setBirthdate(e.target.value)}
                  autoComplete="off"
                  required
                />
              </div>
              {questions.map((q, i) => (
                <div key={q.id}>
                  <Label htmlFor={`ans-${i}`}>{q.label}</Label>
                  <Input
                    id={`ans-${i}`}
                    type="text"
                    value={answers[q.id] ?? ""}
                    onChange={(e) => setAnswers((p) => ({ ...p, [q.id]: e.target.value }))}
                    autoComplete="off"
                    autoCorrect="off"
                    spellCheck={false}
                    data-1p-ignore
                    data-lpignore="true"
                    required
                  />
                </div>
              ))}
              <div>
                <Label htmlFor="rkey">Clé de récupération CHOPCHOP</Label>
                <Input
                  id="rkey"
                  type="text"
                  value={recoveryKey}
                  onChange={(e) => setRecoveryKey(e.target.value.toUpperCase())}
                  placeholder="XXXX-XXXX-XXXX-XXXX-XXXX"
                  autoComplete="off"
                  spellCheck={false}
                  data-1p-ignore
                  data-lpignore="true"
                  className="font-mono tracking-wider"
                  required
                />
              </div>
              <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
                {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Vérifier"}
              </Button>
              <button
                type="button"
                onClick={() => setStep("identify")}
                className="w-full text-[12px] text-muted-foreground"
              >
                ← Recommencer
              </button>
            </form>
          )}

          {step === "password" && (
            <form onSubmit={submitPassword} className="space-y-4">
              <p className="text-[12px] text-muted-foreground" role="status">
                Vérification réussie. Choisissez un nouveau mot de passe ({MIN_PASSWORD_LENGTH}{" "}
                caractères minimum).
              </p>
              <div>
                <Label htmlFor="np">Nouveau mot de passe</Label>
                <Input
                  id="np"
                  type="password"
                  autoComplete="new-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
              </div>
              <div>
                <Label htmlFor="np2">Confirmer le mot de passe</Label>
                <Input
                  id="np2"
                  type="password"
                  autoComplete="new-password"
                  value={password2}
                  onChange={(e) => setPassword2(e.target.value)}
                  required
                />
              </div>
              <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
                {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Changer le mot de passe"}
              </Button>
            </form>
          )}

          {step === "newkey" && (
            <div className="space-y-4">
              <p className="text-[12px] text-muted-foreground" role="status">
                Mot de passe modifié. Toutes vos anciennes sessions ont été fermées. Voici votre
                nouvelle clé de récupération — l'ancienne ne fonctionne plus.
              </p>
              <RecoveryKeyCard
                recoveryKey={newKey}
                onConfirm={() => {
                  setNewKey("");
                  navigate(safeNext ? `/auth?next=${encodeURIComponent(safeNext)}` : "/auth", {
                    replace: true,
                  });
                }}
                confirmLabel="Se connecter"
              />
            </div>
          )}
        </div>

        <Link to="/auth" className="block text-center text-xs text-muted-foreground mt-4 hover:underline">
          ← Retour à la connexion
        </Link>
      </div>
    </div>
  );
}