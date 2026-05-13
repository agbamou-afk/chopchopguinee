import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function SupportAdmin() {
  return (
    <ModulePage module="support" title="Support & Litiges" subtitle="Tickets, conversations, remboursements et incidents sécurité">
      <ComingSoon description="File de tickets, assignation, fil de discussion et notes internes." />
    </ModulePage>
  );
}
