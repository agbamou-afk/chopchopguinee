import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function RepasAdmin() {
  return (
    <ModulePage module="repas" title="Repas Admin" subtitle="Restaurants, menus, commandes et délais de préparation">
      <ComingSoon description="Modération des menus, gestion des commandes, litiges Repas." />
    </ModulePage>
  );
}
