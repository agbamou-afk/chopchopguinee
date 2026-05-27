import { Link } from "react-router-dom";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ArrowRight, Database } from "lucide-react";

export default function ReportsAdmin() {
  return (
    <ModulePage
      module="reports"
      title="Rapports"
      subtitle="Exports opérationnels — pas d'analytique vanité"
    >
      <Card className="p-5 border-dashed">
        <div className="flex items-start gap-3">
          <Database className="w-5 h-5 text-muted-foreground mt-0.5" />
          <div className="space-y-2">
            <p className="text-sm font-semibold">Analytique consolidée — À connecter</p>
            <p className="text-[13px] text-muted-foreground">
              Les indicateurs de revenus, courses et croissance seront branchés sur des sources réelles
              (paiements confirmés, missions livrées, utilisateurs actifs) avant publication.
              Aucune donnée fictive ne sera affichée ici.
            </p>
          </div>
        </div>
      </Card>

      <div className="grid md:grid-cols-2 gap-3">
        <Card className="p-5 space-y-2">
          <p className="text-sm font-semibold">Export paiements</p>
          <p className="text-[12px] text-muted-foreground">
            Filtrer, vérifier et exporter les transactions depuis la réconciliation paiements.
          </p>
          <Link to="/admin/payments">
            <Button size="sm" variant="outline" className="mt-1">
              Ouvrir réconciliation <ArrowRight className="w-3.5 h-3.5 ml-1" />
            </Button>
          </Link>
        </Card>
        <Card className="p-5 space-y-2">
          <p className="text-sm font-semibold">État pilote</p>
          <p className="text-[12px] text-muted-foreground">
            Voir l'état Go/No-Go, missions actives et incidents en cours.
          </p>
          <Link to="/admin/pilot-command">
            <Button size="sm" variant="outline" className="mt-1">
              Pilot Command Center <ArrowRight className="w-3.5 h-3.5 ml-1" />
            </Button>
          </Link>
        </Card>
      </div>
    </ModulePage>
  );
}
