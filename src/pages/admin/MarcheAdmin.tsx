import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function MarcheAdmin() {
  return (
    <ModulePage module="marche" title="Marché Admin" subtitle="Annonces, signalements, vendeurs et catégories">
      <ComingSoon description="Modération des annonces, suspensions, mises en avant." />
    </ModulePage>
  );
}
