import { useCallback, useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Loader2, ShieldAlert } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { useRecoveryStatus } from "@/hooks/useRecoveryStatus";
import { RecoverySetupWizard } from "@/components/recovery/RecoverySetupWizard";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Button } from "@/components/ui/button";
import { Seo } from "@/components/Seo";

/**
 * Mandatory recovery setup.
 *
 * Reached by (a) legacy accounts that signed in without recovery material and
 * (b) new accounts whose enrollment did not complete. Never a dead end: the
 * user keeps their session, their data and their intended destination.
 *
 * Completion is *revalidated against the server* before navigating. The page
 * never leaves on a fire-and-forget refresh, so the globally mounted
 * `RecoverySetupRedirect` can never bounce a just-enrolled user back here.
 */
export default function RecoverySetup() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const nextParam = params.get("next");
  const safeNext =
    nextParam && nextParam.startsWith("/") && !nextParam.startsWith("//") ? nextParam : "/";
  const { ready, isLoggedIn } = useAuth();
  const { configured, loading, reload } = useRecoveryStatus();
  const [phase, setPhase] = useState<"setup" | "finalizing" | "stalled">("setup");

  useEffect(() => {
    if (ready && !isLoggedIn) navigate("/auth", { replace: true });
  }, [ready, isLoggedIn, navigate]);

  useEffect(() => {
    if (!loading && configured) navigate(safeNext, { replace: true });
  }, [loading, configured, safeNext, navigate]);

  // Revalidate against the server; only a fresh `configured=true` releases the
  // gate. Anything else keeps the user here with a retry, never a dead end and
  // never a reset back to a blank step 1.
  const finalize = useCallback(async () => {
    setPhase("finalizing");
    const fresh = await reload(true);
    if (fresh?.configured === true) return; // effect above performs the single redirect
    setPhase("stalled");
  }, [reload]);

  return (
    <div className="min-h-screen bg-background px-4 py-8 flex justify-center">
      <Seo
        title="Sécuriser votre compte — CHOPCHOP"
        description="Configurez la récupération de votre compte CHOPCHOP : date de naissance, questions privées et clé de récupération."
        canonical="/account/recovery-setup"
      />
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-5">
          <BrandLogo size="lg" className="mb-2" />
          <h1 className="text-lg font-bold text-foreground">Sécurisez votre compte</h1>
        </div>

        <div className="flex items-start gap-2 rounded-2xl bg-muted/50 border border-border p-3 mb-4">
          <ShieldAlert className="w-5 h-5 text-primary shrink-0 mt-0.5" aria-hidden />
          <p className="text-[12px] text-muted-foreground leading-snug">
            Configurez la récupération de votre compte pour pouvoir changer votre mot de passe
            vous-même, sans email et sans passer par le support. Cela prend une minute.
          </p>
        </div>

        <div className="bg-card rounded-3xl shadow-elevated p-5">
          {phase === "setup" ? (
            <RecoverySetupWizard mode="enroll" onComplete={() => void finalize()} />
          ) : phase === "finalizing" ? (
            <div
              className="flex flex-col items-center gap-3 py-6 text-center"
              role="status"
              aria-live="polite"
            >
              <Loader2 className="w-6 h-6 animate-spin text-primary" aria-hidden />
              <p className="text-sm text-muted-foreground">Finalisation de la sécurisation…</p>
            </div>
          ) : (
            <div className="space-y-3 text-center py-2" role="alert">
              <p className="text-sm font-semibold text-foreground">
                Configuration enregistrée, vérification impossible
              </p>
              <p className="text-[12px] text-muted-foreground leading-snug">
                Votre clé a bien été confirmée. Nous n'avons pas pu vérifier l'état de votre compte.
                Vérifiez votre connexion puis réessayez.
              </p>
              <Button
                type="button"
                onClick={() => void finalize()}
                className="w-full h-11 gradient-primary"
              >
                Réessayer
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
