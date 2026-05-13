import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { Bike, Activity, Star, Wallet } from "lucide-react";
import { useState } from "react";

const MOCK = [
  { name: "Amadou Diallo", vehicle: "Moto", rating: "4.9", accept: "92%", earnings: "1 240 000", status: "online" },
  { name: "Sékou Camara", vehicle: "TokTok", rating: "4.7", accept: "88%", earnings: "820 000", status: "online" },
  { name: "Mariama Sow", vehicle: "Moto", rating: "4.8", accept: "94%", earnings: "650 000", status: "offline" },
  { name: "Ibrahima Bah", vehicle: "Moto", rating: "4.2", accept: "71%", earnings: "210 000", status: "suspended" },
  { name: "Fatou Touré", vehicle: "TokTok", rating: "5.0", accept: "98%", earnings: "1 580 000", status: "online" },
];

export default function DriversAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="drivers" title="Chauffeurs" subtitle="Gestion, KYC, performances et payouts">
      <StatGrid items={[
        { label: "Chauffeurs actifs", value: "612", icon: Bike, tone: "text-emerald-600" },
        { label: "En ligne", value: "342", icon: Activity, tone: "text-primary" },
        { label: "Note moyenne", value: "4.7", icon: Star, tone: "text-amber-500" },
        { label: "Cash dû", value: "4.2 M GNF", icon: Wallet, tone: "text-rose-600" },
      ]} />
      <AdminToolbar placeholder="Rechercher chauffeur..." right={<Button size="sm" className="gradient-primary">+ Approuver</Button>} />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "En ligne", "Hors ligne", "En course", "Suspendus", "KYC en attente"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["Chauffeur", "Véhicule", "Note", "Acceptation", "Gains 30j (GNF)", "Statut", "Actions"]}
        rows={MOCK.map((d) => [
          <span className="font-medium">{d.name}</span>, d.vehicle,
          <span className="flex items-center gap-1"><Star className="w-3 h-3 text-amber-500 fill-amber-500" />{d.rating}</span>,
          d.accept, d.earnings, <StatusBadge status={d.status} />,
          <div className="flex gap-1">
            <Button size="sm" variant="ghost">Profil</Button>
            <Button size="sm" variant="ghost">Suspendre</Button>
          </div>,
        ])}
      />
    </ModulePage>
  );
}
