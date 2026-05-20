import { SectionCard } from "./SectionCard";
import { Wallet } from "lucide-react";

interface Props {
  enabled: boolean;
}

export function ChopPayActivitySection({ enabled }: Props) {
  return (
    <SectionCard title="CHOPPay" hint={enabled ? "Encaissements activés" : "Non activé"}>
      <div className="flex items-center gap-3 rounded-xl bg-muted/40 border border-border/50 p-3">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
          <Wallet className="w-5 h-5 text-primary" />
        </div>
        <div className="min-w-0">
          <p className="text-sm font-semibold text-foreground">
            {enabled ? "Vos paiements arrivent dans le portefeuille" : "Activez CHOPPay pour recevoir des paiements"}
          </p>
          <p className="text-xs text-muted-foreground">Historique détaillé bientôt disponible.</p>
        </div>
      </div>
    </SectionCard>
  );
}