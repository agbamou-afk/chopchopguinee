import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function LiveOps() {
  return (
    <ModulePage module="live_ops" title="Live Operations" subtitle="Carte temps réel des chauffeurs, courses et livraisons">
      <ComingSoon description="Carte live, alertes incidents, et zones d'opérations en temps réel." />
    </ModulePage>
  );
}