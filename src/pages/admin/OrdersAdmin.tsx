import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function OrdersAdmin() {
  return (
    <ModulePage module="orders" title="Courses & Livraisons" subtitle="Vue temps réel des Moto, TokTok, Envoyer, Repas, Marché">
      <ComingSoon description="Détails par course, réassignation, remboursement, escalade incident." />
    </ModulePage>
  );
}
