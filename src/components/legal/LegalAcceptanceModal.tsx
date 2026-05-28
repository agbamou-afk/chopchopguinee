import { useLocation } from "react-router-dom";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Loader2, ScrollText } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import { useLegalConsentGate, isSensitiveRoute } from "@/hooks/useLegalConsentGate";

const ALWAYS_ALLOW = ["/auth", "/terms", "/privacy", "/legal", "/offline", "/unsubscribe"];

/**
 * Global one-time Terms/Privacy acceptance modal. Renders only when:
 *  - the user is logged in
 *  - they have not accepted the CURRENT legal versions
 *  - the current route is a sensitive surface (booking, wallet, driver, etc.)
 *
 * Public/onboarding/home routes never trigger it.
 */
export function LegalAcceptanceModal() {
  const { pathname } = useLocation();
  const { ready, needsAcceptance, accepting, accept } = useLegalConsentGate();

  if (!ready || !needsAcceptance) return null;
  if (ALWAYS_ALLOW.some((p) => pathname.startsWith(p))) return null;
  if (!isSensitiveRoute(pathname)) return null;

  const onAccept = async () => {
    const res = await accept();
    if (!res.ok) {
      toast({
        title: "Erreur",
        description: "Impossible d'enregistrer votre acceptation. Réessayez.",
      });
    }
  };

  return (
    <Dialog open onOpenChange={() => { /* not dismissible */ }}>
      <DialogContent
        className="max-w-md"
        onPointerDownOutside={(e) => e.preventDefault()}
        onEscapeKeyDown={(e) => e.preventDefault()}
      >
        <DialogHeader>
          <div className="flex items-center gap-2 mb-1">
            <ScrollText className="w-5 h-5 text-primary" />
            <DialogTitle>Conditions mises à jour</DialogTitle>
          </div>
          <DialogDescription className="text-sm text-foreground/80">
            Nous avons mis à jour les Conditions d'utilisation de CHOPCHOP.
            Veuillez les accepter pour continuer.
          </DialogDescription>
        </DialogHeader>

        <ul className="text-sm text-muted-foreground space-y-1 pl-1">
          <li>
            <a href="/terms" target="_blank" rel="noopener" className="text-primary underline">
              Lire les Conditions d'utilisation
            </a>
          </li>
          <li>
            <a href="/privacy" target="_blank" rel="noopener" className="text-primary underline">
              Lire la Politique de confidentialité
            </a>
          </li>
        </ul>

        <Button
          onClick={onAccept}
          disabled={accepting}
          className="w-full h-11 gradient-primary"
        >
          {accepting ? <Loader2 className="w-4 h-4 animate-spin" /> : "J'accepte"}
        </Button>
      </DialogContent>
    </Dialog>
  );
}