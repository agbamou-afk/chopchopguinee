import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function MerchantsAdmin() {
  return (
    <ModulePage module="merchants" title="Marchands" subtitle="Restaurants, boutiques, services et règlements">
      <ComingSoon description="Onboarding, vérification, commissions, horaires, payouts." />
    </ModulePage>
  );
}
