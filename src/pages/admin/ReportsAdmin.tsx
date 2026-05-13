import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function ReportsAdmin() {
  return (
    <ModulePage module="reports" title="Rapports" subtitle="Revenus, performances et exports financiers">
      <ComingSoon description="Rapports quotidiens et exports CSV (Finance/Super Admin)." />
    </ModulePage>
  );
}
