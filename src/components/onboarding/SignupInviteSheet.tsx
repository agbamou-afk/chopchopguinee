import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { useNavigate } from "react-router-dom";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { useEffect } from "react";
import { BrandLogo } from "@/components/brand/BrandLogo";
import conakryScene from "@/assets/brand/conakry-street-scene.jpg";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onDismiss: () => void;
}

/**
 * Gentle post-onboarding signup invitation for logged-out users. Non-blocking:
 * users can dismiss and keep exploring. Real auth is still enforced later by
 * ConversionGateSheet at commitment points.
 */
export function SignupInviteSheet({ open, onOpenChange, onDismiss }: Props) {
  const navigate = useNavigate();

  useEffect(() => {
    if (open) Analytics.track("signup_invite_shown");
  }, [open]);

  const handleCreate = () => {
    Analytics.track("signup_invite_create_account_clicked");
    onOpenChange(false);
    navigate("/auth?intent=client&next=/");
  };

  const handleSignin = () => {
    Analytics.track("signup_invite_signin_clicked");
    onOpenChange(false);
    navigate("/auth?next=/");
  };

  const handleDismiss = () => {
    Analytics.track("signup_invite_dismissed");
    onDismiss();
    onOpenChange(false);
  };

  return (
    <Sheet
      open={open}
      onOpenChange={(o) => {
        if (!o) handleDismiss();
        else onOpenChange(o);
      }}
    >
      <SheetContent
        side="bottom"
        className="rounded-t-3xl pb-[calc(env(safe-area-inset-bottom)+1.5rem)] bg-card border-t border-border/60 overflow-hidden px-5"
      >
        {/* Subtle branded Conakry background illustration */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 bottom-0 h-56 bg-no-repeat bg-bottom bg-contain opacity-[0.08]"
          style={{ backgroundImage: `url(${conakryScene})` }}
        />
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-gradient-to-b from-card via-card/95 to-card/70"
        />

        <div className="relative">
          <div className="mx-auto w-12 h-1.5 rounded-full bg-muted mb-5" aria-hidden />

          <div className="flex items-center justify-center mb-4">
            <div className="w-16 h-16 rounded-2xl bg-background ring-1 ring-border/60 shadow-card flex items-center justify-center">
              <BrandLogo size="md" className="!h-10" />
            </div>
          </div>

          <SheetHeader className="text-center px-1">
            <SheetTitle className="text-[20px] leading-tight font-bold text-foreground">
              Créez votre compte pour tout faire avec CHOPCHOP
            </SheetTitle>
            <SheetDescription className="text-sm leading-relaxed text-muted-foreground mx-auto max-w-[34ch]">
              Un compte vous permet de réserver une course, commander un repas,
              acheter au marché, recharger ChopWallet et suivre vos opérations
              en toute simplicité.
            </SheetDescription>
          </SheetHeader>

          <div className="grid gap-2.5 mt-6">
            <Button
              className="h-12 gradient-cta text-primary-foreground font-semibold shadow-elevated"
              onClick={handleCreate}
            >
              Créer mon compte
            </Button>
            <Button
              variant="outline"
              className="h-12 border-primary/30 text-primary hover:bg-primary/5 font-medium"
              onClick={handleSignin}
            >
              J'ai déjà un compte
            </Button>
            <Button
              variant="ghost"
              className="h-10 text-muted-foreground text-sm"
              onClick={handleDismiss}
            >
              Continuer à explorer
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}

export const SIGNUP_INVITE_DISMISSED_KEY = "cc_signup_invite_dismissed_at";
export const SIGNUP_INVITE_SESSION_KEY = "cc_signup_invite_seen_session";

/** Returns true if invite was dismissed within the last 24h or seen this session. */
export function shouldSkipSignupInvite(): boolean {
  if (typeof window === "undefined") return true;
  try {
    if (sessionStorage.getItem(SIGNUP_INVITE_SESSION_KEY) === "1") return true;
    const raw = localStorage.getItem(SIGNUP_INVITE_DISMISSED_KEY);
    if (!raw) return false;
    const ts = Number(raw);
    if (!Number.isFinite(ts)) return false;
    return Date.now() - ts < 24 * 60 * 60 * 1000;
  } catch {
    return false;
  }
}

export function markSignupInviteDismissed() {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.setItem(SIGNUP_INVITE_SESSION_KEY, "1");
    localStorage.setItem(SIGNUP_INVITE_DISMISSED_KEY, String(Date.now()));
  } catch { /* noop */ }
}

export function markSignupInviteSeenSession() {
  if (typeof window === "undefined") return;
  try { sessionStorage.setItem(SIGNUP_INVITE_SESSION_KEY, "1"); } catch { /* noop */ }
}