import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Megaphone } from "lucide-react";

export default function PromotionsAdmin() {
  return (
    <ModulePage module="promotions" title="Promotions" subtitle="Codes promo et campagnes">
      <Card className="p-5 border-dashed">
        <div className="flex items-start gap-3">
          <Megaphone className="w-5 h-5 text-muted-foreground mt-0.5" />
          <div className="space-y-2">
            <p className="text-sm font-semibold">Promotions — À connecter</p>
            <p className="text-[13px] text-muted-foreground">
              Aucune table de promotions opérationnelle n'est encore branchée. Aucun code promo
              fictif n'est affiché ici. Le module sera activé dès qu'une source réelle (codes, campagnes,
              parrainage) sera disponible.
            </p>
          </div>
        </div>
      </Card>
    </ModulePage>
  );
}
