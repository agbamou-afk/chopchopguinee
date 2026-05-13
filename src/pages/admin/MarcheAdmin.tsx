import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { ShoppingBag, Flag, Eye, TrendingUp } from "lucide-react";
import { useState } from "react";

const ROWS = [
  { id: "ML-9981", title: "iPhone 13 Pro", seller: "Mariama D.", price: "8 500 000", views: 412, reports: 0, status: "active" },
  { id: "ML-9980", title: "Frigidaire LG", seller: "Sékou C.", price: "4 200 000", views: 89, reports: 2, status: "open" },
  { id: "ML-9979", title: "Service plomberie", seller: "Ibrahima B.", price: "—", views: 156, reports: 1, status: "investigating" },
  { id: "ML-9978", title: "Lit double + matelas", seller: "Fatou T.", price: "1 800 000", views: 34, reports: 0, status: "active" },
];

export default function MarcheAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="marche" title="Marché Admin" subtitle="Annonces, signalements et modération">
      <StatGrid items={[
        { label: "Annonces actives", value: "3 921", icon: ShoppingBag, tone: "text-emerald-600" },
        { label: "Signalements", value: "47", icon: Flag, tone: "text-rose-600" },
        { label: "Vues 7j", value: "184k", icon: Eye, tone: "text-primary" },
        { label: "Boostées", value: "23", icon: TrendingUp, tone: "text-amber-600" },
      ]} />
      <AdminToolbar placeholder="Rechercher annonce..." />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Actives", "Signalées", "Suspendues", "Boostées"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable columns={["ID", "Annonce", "Vendeur", "Prix (GNF)", "Vues", "Signalements", "Statut", "Actions"]}
        rows={ROWS.map((r) => [r.id, <span className="font-medium">{r.title}</span>, r.seller, r.price, r.views, r.reports,
          <StatusBadge status={r.status} />,
          <div className="flex gap-1">
            <Button size="sm" variant="ghost">Voir</Button>
            <Button size="sm" variant="ghost" className="text-rose-600">Suspendre</Button>
          </div>])} />
    </ModulePage>
  );
}
