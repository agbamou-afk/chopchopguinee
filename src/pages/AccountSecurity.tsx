import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, KeyRound, Loader2, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PasswordInput } from "@/components/ui/password-input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { Seo } from "@/components/Seo";
import { useAuth } from "@/contexts/AuthContext";
import { useRecoveryStatus } from "@/hooks/useRecoveryStatus";
import { RecoverySetupWizard } from "@/components/recovery/RecoverySetupWizard";
import { changePasswordSelf } from "@/lib/recovery/api";
import { MIN_PASSWORD_LENGTH, questionLabel } from "@/lib/recovery/questions";

/**
 * Compte → Sécurité.
 *
 * Lets a signed-in user change their password and rotate their recovery
 * material. Existing answers and the previous recovery key are never shown —
 * only whether recovery is configured, and which prompts were chosen.
 */
export default function AccountSecurity() {
  const navigate = useNavigate();
  const { ready, isLoggedIn } = useAuth();
  const { status, loading, reload, configured } = useRecoveryStatus();
  const [rotating, setRotating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [next2, setNext2] = useState("");

  if (ready && !isLoggedIn) {
    navigate("/auth?next=/account/security", { replace: true });
  }

  const submitPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (next.length < MIN_PASSWORD_LENGTH) {
      toast({
        title: "Mot de passe trop court",
        description: `Utilisez au moins ${MIN_PASSWORD_LENGTH} caractères.`,
      });
      return;
    }
    if (next !== next2) {
      toast({ title: "Confirmation", description: "Les deux mots de passe ne correspondent pas." });
      return;
    }
    setBusy(true);
    const res = await changePasswordSelf({ current_password: current, new_password: next });
    setBusy(false);
    if (!res.ok) {
      toast({ title: "Échec", description: res.message ?? "Réessayez." });
      return;
    }
    setCurrent("");
    setNext("");
    setNext2("");
    toast({ title: "Mot de passe modifié", description: "Votre nouveau mot de passe est actif." });
  };

  return (
    <div className="min-h-screen bg-background pb-16">
      <Seo
        title="Sécurité du compte — CHOPCHOP"
        description="Changez votre mot de passe CHOPCHOP et gérez vos questions et votre clé de récupération."
        canonical="/account/security"
      />
      <header className="flex items-center gap-3 px-4 py-4 border-b border-border">
        <Link to="/" aria-label="Retour" className="text-muted-foreground">
          <ArrowLeft className="w-5 h-5" />
        </Link>
        <h1 className="text-base font-bold text-foreground">Sécurité</h1>
      </header>

      <main className="px-4 py-4 space-y-4 max-w-md mx-auto">
        <section className="bg-card rounded-3xl shadow-card p-4 space-y-3">
          <div className="flex items-center gap-2">
            <KeyRound className="w-4 h-4 text-primary" aria-hidden />
            <h2 className="text-sm font-semibold text-foreground">Changer le mot de passe</h2>
          </div>
          <form onSubmit={submitPassword} className="space-y-3">
            <div>
              <Label htmlFor="cur">Mot de passe actuel</Label>
              <PasswordInput
                id="cur"
                autoComplete="current-password"
                value={current}
                onChange={(e) => setCurrent(e.target.value)}
                required
              />
            </div>
            <div>
              <Label htmlFor="nx">Nouveau mot de passe</Label>
              <PasswordInput
                id="nx"
                autoComplete="new-password"
                value={next}
                onChange={(e) => setNext(e.target.value)}
                required
              />
            </div>
            <div>
              <Label htmlFor="nx2">Confirmer</Label>
              <PasswordInput
                id="nx2"
                autoComplete="new-password"
                value={next2}
                onChange={(e) => setNext2(e.target.value)}
                required
              />
            </div>
            <Button type="submit" disabled={busy} className="w-full h-11 gradient-primary">
              {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Mettre à jour"}
            </Button>
          </form>
        </section>

        <section className="bg-card rounded-3xl shadow-card p-4 space-y-3">
          <div className="flex items-center gap-2">
            <ShieldCheck className="w-4 h-4 text-primary" aria-hidden />
            <h2 className="text-sm font-semibold text-foreground">Récupération du compte</h2>
          </div>

          {loading ? (
            <p className="text-xs text-muted-foreground">Chargement…</p>
          ) : (
            <p className="text-xs text-muted-foreground">
              {configured
                ? "Récupération du compte configurée."
                : "Récupération non configurée. Configurez-la pour pouvoir réinitialiser votre mot de passe seul."}
            </p>
          )}

          {configured && (status?.question_ids?.length ?? 0) > 0 && (
            <ul className="space-y-1 list-disc pl-4">
              {status!.question_ids.map((id) => (
                <li key={id} className="text-[11px] text-muted-foreground leading-snug">
                  {questionLabel(id)}
                </li>
              ))}
            </ul>
          )}

          {rotating ? (
            <div className="pt-1">
              <RecoverySetupWizard
                mode={configured ? "rotate" : "enroll"}
                onComplete={() => {
                  setRotating(false);
                  void reload();
                }}
              />
              <button
                type="button"
                onClick={() => setRotating(false)}
                className="w-full text-[12px] text-muted-foreground pt-3"
              >
                Annuler
              </button>
            </div>
          ) : (
            <Button
              type="button"
              variant="outline"
              onClick={() => setRotating(true)}
              className="w-full h-11"
            >
              {configured
                ? "Changer mes questions et ma clé"
                : "Configurer la récupération"}
            </Button>
          )}

          <p className="text-[11px] text-muted-foreground leading-snug">
            Vos réponses et votre clé ne sont jamais réaffichées. L'équipe CHOPCHOP ne peut ni les
            voir ni réinitialiser votre mot de passe à votre place.
          </p>
        </section>
      </main>
    </div>
  );
}