import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";

const TOGGLES = [
  { label: "Mode sombre (admin)", desc: "Active l'interface admin en thème sombre", on: false },
  { label: "Notifications email admin", desc: "Recevoir les alertes critiques par email", on: true },
  { label: "Audit log détaillé", desc: "Enregistrer toutes les actions admin", on: true },
  { label: "Maintenance mode", desc: "Couper temporairement l'accès clients", on: false },
];

export default function SettingsAdmin() {
  return (
    <ModulePage module="settings" title="Paramètres" subtitle="Configuration plateforme et préférences admin">
      <Card className="p-5 divide-y">
        {TOGGLES.map((t) => (
          <div key={t.label} className="flex items-center justify-between py-4 first:pt-0 last:pb-0">
            <div className="min-w-0">
              <Label className="text-sm font-medium">{t.label}</Label>
              <p className="text-xs text-muted-foreground">{t.desc}</p>
            </div>
            <Switch defaultChecked={t.on} />
          </div>
        ))}
      </Card>
      <Card className="p-5">
        <p className="text-sm font-semibold mb-2">Mentions légales & CGU</p>
        <p className="text-xs text-muted-foreground">CHOP GUINEE LTD — version 2026.05 · dernière mise à jour il y a 12 jours</p>
      </Card>
    </ModulePage>
  );
}
