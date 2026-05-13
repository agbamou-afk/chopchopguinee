import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function RiskAdmin() {
  return (
    <ModulePage module="risk" title="Fraude / Risque" subtitle="Alertes, scores de risque et gel de comptes">
      <ComingSoon description="Détection d'anomalies wallet, agents et marketplace, actions rapides." />
    </ModulePage>
  );
}
