import { useCallback, useEffect, useState } from "react";
import { Loader2, ShieldAlert } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { toast } from "@/hooks/use-toast";
import { ServicePolicyEditor } from "@/components/admin/finance/ServicePolicyEditor";
import { FinanceControlsPanel } from "@/components/admin/finance/FinanceControlsPanel";
import { RepasPromotionsPanel } from "@/components/admin/finance/RepasPromotionsPanel";
import {
  FinancePolicyRow, MISSION_LABELS, MISSION_TYPES, loadPolicies,
} from "@/lib/admin/financePolicy";

/**
 * Slice 2 — finance policy control plane.
 * Every economic value shown here is read from the append-only policy tables and
 * every change is written through an audited, effective-dated God Admin RPC.
 * Nothing on this page is authoritative and nothing here is retroactive.
 */
export default function FinancePolicyAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [rows, setRows] = useState<FinancePolicyRow[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setRows(await loadPolicies());
    } catch (e) {
      toast({ title: "Chargement impossible", description: (e as Error).message, variant: "destructive" });
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  return (
    <ModulePage
      module="pricing"
      title="Politique financière"
      subtitle="Commission, caution, frais, annulation et activation — écriture réservée au God Admin"
    >
      {!isSuperAdmin && (
        <Card className="p-3 mb-3 flex items-center gap-2 text-xs text-muted-foreground">
          <ShieldAlert className="w-4 h-4" />
          Lecture seule. Seul un God Admin peut modifier la politique financière.
        </Card>
      )}

      {loading ? (
        <Loader2 className="w-5 h-5 animate-spin" />
      ) : (
        <Tabs defaultValue="ride">
          <TabsList className="flex-wrap h-auto">
            {MISSION_TYPES.map((t) => (
              <TabsTrigger key={t} value={t}>{MISSION_LABELS[t]}</TabsTrigger>
            ))}
            <TabsTrigger value="controls">Contrôles &amp; activation</TabsTrigger>
            <TabsTrigger value="repas-promos">Campagnes Repas</TabsTrigger>
          </TabsList>

          {MISSION_TYPES.map((t) => (
            <TabsContent key={t} value={t} className="mt-3">
              <ServicePolicyEditor
                missionType={t}
                rows={rows}
                canEdit={isSuperAdmin}
                onSaved={load}
              />
            </TabsContent>
          ))}

          <TabsContent value="controls" className="mt-3">
            <FinanceControlsPanel isGodAdmin={isSuperAdmin} />
          </TabsContent>

          <TabsContent value="repas-promos" className="mt-3">
            <RepasPromotionsPanel isGodAdmin={isSuperAdmin} />
          </TabsContent>
        </Tabs>
      )}

      <p className="text-[11px] text-muted-foreground mt-4">
        Les missions, commandes et paiements déjà acceptés conservent l'instantané de politique
        enregistré au moment de l'acceptation. Aucune modification n'est rétroactive et aucune
        transaction terminée n'est recalculée.
      </p>
    </ModulePage>
  );
}
