import { useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ShieldAlert } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { useRecoveryStatus } from "@/hooks/useRecoveryStatus";
import { RecoverySetupWizard } from "@/components/recovery/RecoverySetupWizard";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Seo } from "@/components/Seo";

/**
 * Mandatory recovery setup.
 *
 * Reached by (a) legacy accounts that signed in without recovery material and
 * (b) new accounts whose enrollment did not complete. Never a dead end: the
 * user keeps their session, their data and their intended destination.
 */
export default function RecoverySetup() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const nextParam = params.get("next");
  const safeNext = nextParam && nextParam.startsWith("/") ? nextParam : "/";
  const { ready, isLoggedIn } = useAuth();
  const { configured, loading, reload } = useRecoveryStatus();

  useEffect(() => {
    if (ready && !isLoggedIn) navigate("/auth", { replace: true });
  }, [ready, isLoggedIn, navigate]);

  useEffect(() => {
    if (!loading && configured) navigate(safeNext, { replace: true });
  }, [loading, configured, safeNext, navigate]);

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
          <RecoverySetupWizard mode="enroll" onComplete={() => { void reload(); navigate(safeNext, { replace: true }); }} />
        </div>
      </div>
    </div>
  );
}