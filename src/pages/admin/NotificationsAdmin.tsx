import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
export default function NotificationsAdmin() {
  return (
    <ModulePage module="notifications" title="Notifications" subtitle="Templates WhatsApp, SMS, push et campagnes">
      <ComingSoon description="Gestion des templates, envoi ciblé et journal des messages." />
    </ModulePage>
  );
}
