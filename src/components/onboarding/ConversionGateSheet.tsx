import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { useNavigate } from "react-router-dom";
import { Bike, LogIn, UserPlus, SteeringWheel as SteeringIcon } from "lucide-react";

export type ConversionIntent = "client" | "driver" | "wallet" | "ride" | "order" | "message" | "pay";

interface Props {
  open: boolean;
  intent?: ConversionIntent;
  onOpenChange: (open: boolean) => void;
  onExploreDriverDemo: () => void;
}

/**
 * Shown when a public/demo client tries to take a real action (recharge,
 * confirm a real ride, place an order, message a seller, pay with CHOPPay).
 * Lets them either create an account, log in, or jump into the driver demo.
 */
export function ConversionGateSheet({ open, intent, onOpenChange, onExploreDriverDemo }: Props) {
  const navigate = useNavigate();
  const subtitle = (() => {
    switch (intent) {
      case "wallet": return "Créez un compte pour recharger votre CHOPWallet.";
      case "ride": return "Créez un compte pour confirmer votre course.";
      case "order": return "Créez un compte pour passer commande.";
      case "message": return "Connectez-vous pour discuter avec le vendeur.";
      case "pay": return "Connectez-vous pour payer avec CHOPPay.";
      default: return "Connectez-vous ou créez un compte pour continuer.";
    }
  })();

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl pb-8">
        <SheetHeader className="text-left">
          <SheetTitle>Prêt à utiliser CHOP CHOP ?</SheetTitle>
          <SheetDescription>{subtitle}</SheetDescription>
        </SheetHeader>
        <div className="grid gap-2 mt-4">
          <Button
            className="h-12 justify-start gradient-primary"
            onClick={() => { onOpenChange(false); navigate("/auth?intent=client"); }}
          >
            <UserPlus className="w-4 h-4 mr-2" /> Créer un compte client
          </Button>
          <Button
            variant="outline"
            className="h-12 justify-start"
            onClick={() => { onOpenChange(false); onExploreDriverDemo(); }}
          >
            <Bike className="w-4 h-4 mr-2" /> Explorer le mode chauffeur
          </Button>
          <Button
            variant="outline"
            className="h-12 justify-start"
            onClick={() => { onOpenChange(false); navigate("/auth?intent=driver"); }}
          >
            <SteeringIcon className="w-4 h-4 mr-2" /> Devenir chauffeur
          </Button>
          <Button
            variant="ghost"
            className="h-12 justify-start"
            onClick={() => { onOpenChange(false); navigate("/auth"); }}
          >
            <LogIn className="w-4 h-4 mr-2" /> Se connecter
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}
