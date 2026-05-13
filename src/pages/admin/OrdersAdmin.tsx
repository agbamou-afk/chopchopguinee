import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { ClipboardList, CheckCircle2, X, RefreshCw } from "lucide-react";
import { useState } from "react";

const ROWS = [
  { id: "CC-RD-9881", type: "Moto", client: "Mariama D.", driver: "Amadou D.", fare: "12 000", status: "active", time: "10:42" },
  { id: "CC-LV-7720", type: "Repas", client: "Sékou C.", driver: "Fatou T.", fare: "28 500", status: "active", time: "10:38" },
  { id: "CC-RD-9879", type: "TokTok", client: "Ibrahima B.", driver: "Sékou C.", fare: "18 000", status: "completed", time: "10:21" },
  { id: "CC-RD-9876", type: "Moto", client: "Fatou C.", driver: "—", fare: "—", status: "failed", time: "09:58" },
];

export default function OrdersAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="orders" title="Courses & Livraisons" subtitle="Vue temps réel de tous les services">
      <StatGrid items={[
        { label: "Aujourd'hui", value: "1 842", icon: ClipboardList, tone: "text-primary" },
        { label: "Complétées", value: "1 612", icon: CheckCircle2, tone: "text-emerald-600" },
        { label: "Annulées", value: "94", icon: X, tone: "text-rose-600" },
        { label: "Remboursements", value: "5", icon: RefreshCw, tone: "text-amber-600" },
      ]} />
      <AdminToolbar placeholder="Rechercher course / livraison..." />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Moto", "TokTok", "Envoyer", "Repas", "Marché"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["ID", "Service", "Client", "Chauffeur", "Tarif (GNF)", "Statut", "Heure", "Actions"]}
        rows={ROWS.map((r) => [
          <span className="font-mono text-xs">{r.id}</span>, r.type, r.client, r.driver, r.fare,
          <StatusBadge status={r.status} />, r.time,
          <div className="flex gap-1">
            <Button size="sm" variant="ghost">Détails</Button>
            <Button size="sm" variant="ghost">Rembourser</Button>
          </div>,
        ])}
      />
    </ModulePage>
  );
}
