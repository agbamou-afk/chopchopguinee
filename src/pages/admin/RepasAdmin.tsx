import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { UtensilsCrossed, Clock, CheckCircle2, AlertTriangle } from "lucide-react";
import { useState } from "react";

const ROWS = [
  { id: "RP-2210", restaurant: "Le Damier", items: 3, total: "85 000", prep: "12 min", status: "active" },
  { id: "RP-2209", restaurant: "Chez Mariama", items: 2, total: "42 000", prep: "8 min", status: "completed" },
  { id: "RP-2208", restaurant: "Foutah Grill", items: 5, total: "180 000", prep: "Retard +6 min", status: "escalated" },
];

export default function RepasAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="repas" title="Repas Admin" subtitle="Restaurants, menus, commandes et délais">
      <StatGrid items={[
        { label: "Commandes/jour", value: "612", icon: UtensilsCrossed, tone: "text-orange-600" },
        { label: "Délai moyen", value: "23 min", icon: Clock, tone: "text-primary" },
        { label: "Complétées", value: "534", icon: CheckCircle2, tone: "text-emerald-600" },
        { label: "Litiges", value: "4", icon: AlertTriangle, tone: "text-rose-600" },
      ]} />
      <AdminToolbar placeholder="Rechercher restaurant ou commande..." />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "En cours", "En préparation", "Livrées", "Litiges"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable columns={["ID", "Restaurant", "Articles", "Total (GNF)", "Préparation", "Statut", "Actions"]}
        rows={ROWS.map((r) => [r.id, r.restaurant, r.items, r.total, r.prep, <StatusBadge status={r.status} />,
          <Button size="sm" variant="ghost">Détails</Button>])} />
    </ModulePage>
  );
}
