import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function UsersAdmin() {
  return (
    <ModulePage module="users" title="Utilisateurs" subtitle="Recherche, KYC, suspensions, remboursements et notes internes">
      <ComingSoon description="Recherche multi-critères, profil utilisateur complet, actions de modération." />
    </ModulePage>
  );
}
