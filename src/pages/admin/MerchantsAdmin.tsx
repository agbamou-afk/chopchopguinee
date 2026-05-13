import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { Store, CheckCircle2, Clock, TrendingUp } from "lucide-react";
import { useState } from "react";

const MOCK = [
  { name: "Le Damier", type: "Restaurant", orders: 142, balance: "2 340 000 GNF", status: "active", verified: true },
  { name: "Pharmacie Niger", type: "Pharmacie", orders: 87, balance: "890 000 GNF", status: "active", verified: true },
  { name: "Boutique Kaba", type: "Boutique", orders: 23, balance: "120 000 GNF", status: "pending", verified: false },
  { name: "Chez Mariama", type: "Restaurant", orders: 312, balance: "5 120 000 GNF", status: "active", verified: true },
  { name: "Marché Madina", type: "Vendeur", orders: 9, balance: "45 000 GNF", status: "suspended", verified: false },
];

export default function MerchantsAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="merchants" title="Marchands" subtitle="Restaurants, boutiques, pharmacies et services">
      <StatGrid items={[
        { label: "Marchands", value: "186", icon: Store },
        { label: "Vérifiés", value: "164", icon: CheckCircle2, tone: "text-emerald-600" },
        { label: "En attente", value: "12", icon: Clock, tone: "text-amber-600" },
        { label: "CA semaine", value: "48 M GNF", icon: TrendingUp, tone: "text-primary" },
      ]} />
      <AdminToolbar placeholder="Rechercher marchand..." />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Restaurants", "Pharmacies", "Boutiques", "Vendeurs Marché", "En attente"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["Marchand", "Type", "Commandes", "Solde", "Statut", "Actions"]}
        rows={MOCK.map((m) => [
          <span className="font-medium flex items-center gap-2">{m.name}{m.verified && <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />}</span>,
          m.type, m.orders, m.balance, <StatusBadge status={m.status} />,
          <div className="flex gap-1">
            <Button size="sm" variant="ghost">Voir</Button>
            <Button size="sm" variant="ghost">Mettre en avant</Button>
          </div>,
        ])}
      />
    </ModulePage>
  );
}
