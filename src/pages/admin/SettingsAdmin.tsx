import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function SettingsAdmin() {
  return (
    <ModulePage module="settings" title="Paramètres" subtitle="Paramètres légaux, juridique et plateforme">
      <ComingSoon description="Mentions légales, CGU, configuration plateforme." />
    </ModulePage>
  );
}
