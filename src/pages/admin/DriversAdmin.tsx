import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function DriversAdmin() {
  return (
    <ModulePage module="drivers" title="Chauffeurs" subtitle="Approbation, KYC, performances, paiements et zones">
      <ComingSoon description="Liste filtrable, profil détaillé, validation de documents et payouts." />
    </ModulePage>
  );
}
