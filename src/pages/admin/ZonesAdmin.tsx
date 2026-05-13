import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function ZonesAdmin() {
  return (
    <ModulePage module="zones" title="Zones" subtitle="Pays, villes, communes et quartiers">
      <ComingSoon description="Définition des zones de service, restrictions et tarification." />
    </ModulePage>
  );
}
