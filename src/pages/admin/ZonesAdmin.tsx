import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { MapPin, Globe, Building2, Map } from "lucide-react";

const ZONES = [
  { country: "Guinée", city: "Conakry", commune: "Kaloum", neighborhoods: 8, status: "active" },
  { country: "Guinée", city: "Conakry", commune: "Dixinn", neighborhoods: 12, status: "active" },
  { country: "Guinée", city: "Conakry", commune: "Ratoma", neighborhoods: 15, status: "active" },
  { country: "Guinée", city: "Conakry", commune: "Matam", neighborhoods: 10, status: "active" },
  { country: "Guinée", city: "Coyah", commune: "Centre", neighborhoods: 6, status: "pending" },
];

export default function ZonesAdmin() {
  return (
    <ModulePage module="zones" title="Zones" subtitle="Pays, villes, communes et quartiers"
      actions={<Button size="sm" className="gradient-primary"><MapPin className="w-4 h-4 mr-1" /> Ajouter zone</Button>}>
      <StatGrid items={[
        { label: "Pays", value: "1", icon: Globe },
        { label: "Villes", value: "4", icon: Building2, tone: "text-primary" },
        { label: "Communes", value: "12", icon: Map, tone: "text-emerald-600" },
        { label: "Quartiers", value: "184", icon: MapPin, tone: "text-amber-600" },
      ]} />
      <div className="space-y-2">
        {ZONES.map((z, i) => (
          <Card key={i} className="p-4 flex items-center gap-3 hover:shadow-soft transition-all">
            <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center">
              <MapPin className="w-5 h-5 text-primary-foreground" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-sm">{z.commune}</p>
              <p className="text-xs text-muted-foreground">{z.city} · {z.country} · {z.neighborhoods} quartiers</p>
            </div>
            <StatusBadge status={z.status} />
            <Button size="sm" variant="ghost">Éditer</Button>
          </Card>
        ))}
      </div>
    </ModulePage>
  );
}
