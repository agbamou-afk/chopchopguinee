import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function PromotionsAdmin() {
  return (
    <ModulePage module="promotions" title="Promotions" subtitle="Codes promo, campagnes et bonus de parrainage">
      <ComingSoon description="Création et suivi des promos par service, ville et type d'utilisateur." />
    </ModulePage>
  );
}
