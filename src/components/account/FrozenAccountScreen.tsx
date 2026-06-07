import { Snowflake, LifeBuoy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useAuth } from "@/contexts/AuthContext";

const TYPE_LABELS: Record<string, string> = {
  admin_review: "Vérification administrative",
  payment_review: "Vérification de paiement",
  security_review: "Vérification de sécurité",
  dispute: "Litige en cours",
  document_review: "Vérification de documents",
};

export function FrozenAccountScreen() {
  const { freeze, signOut } = useAuth();
  if (!freeze) return null;
  return (
    <div className="min-h-[100dvh] w-full bg-app-conakry flex items-center justify-center p-4">
      <Card className="max-w-md w-full p-6 space-y-4">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center">
            <Snowflake className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-lg font-semibold">Compte temporairement gelé</h1>
            <p className="text-xs text-muted-foreground">
              {TYPE_LABELS[freeze.freeze_type] ?? "Vérification CHOPCHOP"}
            </p>
          </div>
        </div>
        <p className="text-sm">
          Votre compte est en cours de vérification par l'équipe CHOPCHOP.
        </p>
        <div className="rounded-lg bg-muted/40 p-3 text-sm">
          <p className="text-xs uppercase tracking-wide text-muted-foreground mb-1">Raison</p>
          <p className="font-medium">{freeze.reason}</p>
        </div>
        <p className="text-xs text-muted-foreground">
          Vous serez notifié dès que la situation sera résolue. Aucune action sensible
          (commande, course, recharge, publication) n'est possible pendant le gel.
        </p>
        <div className="flex flex-col gap-2">
          <Button asChild className="gradient-primary">
            <a href="mailto:support@chopchopguinee.com?subject=Compte%20gel%C3%A9">
              <LifeBuoy className="w-4 h-4 mr-2" /> Contacter le support
            </a>
          </Button>
          <Button variant="outline" onClick={() => signOut()}>
            Se déconnecter
          </Button>
        </div>
      </Card>
    </div>
  );
}