import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { useNavigate } from "react-router-dom";
import { Sparkles } from "lucide-react";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { useEffect } from "react";

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
        className="rounded-t-3xl pb-[calc(env(safe-area-inset-bottom)+1.5rem)] bg-card border-t border-border/60"
      >
        <div className="mx-auto w-12 h-1.5 rounded-full bg-muted mb-4" aria-hidden />
        <div className="flex items-center justify-center mb-3">
          <div className="w-14 h-14 rounded-2xl gradient-primary flex items-center justify-center shadow-soft">
            <Sparkles className="w-7 h-7 text-primary-foreground" />
          </div>
        </div>
        <SheetHeader className="text-center">
          <SheetTitle className="text-xl">Prêt à tout faire avec CHOPCHOP ?</SheetTitle>
          <SheetDescription className="text-sm leading-relaxed">
            Créez votre compte pour réserver une course, commander un repas,
            acheter au marché et suivre vos paiements dans ChopWallet.
          </SheetDescription>
        </SheetHeader>
        <div className="grid gap-2 mt-5">
          <Button className="h-12 gradient-cta text-primary-foreground font-semibold" onClick={handleCreate}>
            Créer mon compte
          </Button>
          <Button variant="ghost" className="h-11 text-muted-foreground" onClick={handleDismiss}>
            Continuer à explorer
          </Button>
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