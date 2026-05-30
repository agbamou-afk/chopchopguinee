import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ArrowRight, Smartphone, FileText } from "lucide-react";
import { Link } from "react-router-dom";

export default function SettingsAdmin() {
  return (
    <ModulePage module="settings" title="Paramètres" subtitle="Configuration plateforme">
      <Card className="p-5 space-y-3">
        <div className="flex items-start gap-3">
          <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
            <Smartphone className="w-5 h-5 text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold">Comptes Orange Money</p>
            <p className="text-xs text-muted-foreground">
              Les numéros marchand OM affichés aux clients sont gérés dans Réconciliation OM → Comptes OM.
            </p>
          </div>
        </div>
        <Link to="/admin/wallet/reconciliation">
          <Button size="sm" variant="outline">
            Ouvrir Comptes OM <ArrowRight className="w-3.5 h-3.5 ml-1" />
          </Button>
        </Link>
      </Card>

      <Card className="p-5 space-y-2">
        <div className="flex items-start gap-3">
          <FileText className="w-5 h-5 text-muted-foreground mt-0.5" />
          <div className="space-y-1">
            <p className="text-sm font-semibold">Mentions légales & CGU</p>
            <p className="text-xs text-muted-foreground">CHOPCHOP GUINEE LTD — voir page publique pour la version en vigueur.</p>
          </div>
        </div>
      </Card>

      <Card className="p-5 border-dashed">
        <p className="text-sm font-semibold mb-1">Autres préférences — À connecter</p>
        <p className="text-[13px] text-muted-foreground">
          Bascules audit, maintenance et notifications admin seront branchées dès que les
          drapeaux opérationnels seront stockés en base. Aucun toggle fictif n'est exposé ici.
        </p>
      </Card>
    </ModulePage>
  );
}
