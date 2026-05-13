import { ModulePage } from "@/components/admin/ModulePage";
import { AdminToolbar, DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { Users, UserCheck, UserX, ShieldAlert, Eye, Snowflake, MessageSquare } from "lucide-react";
import { useState } from "react";

const MOCK = [
  { name: "Mariama Diallo", phone: "+224 622 11 22 33", wallet: "85 000 GNF", status: "active", joined: "12/03/2026", risk: "low" },
  { name: "Amadou Bah", phone: "+224 620 88 77 66", wallet: "1 240 000 GNF", status: "active", joined: "02/01/2026", risk: "low" },
  { name: "Ibrahima Sow", phone: "+224 628 44 55 66", wallet: "12 000 GNF", status: "suspended", joined: "18/11/2025", risk: "high" },
  { name: "Fatou Camara", phone: "+224 625 33 44 55", wallet: "320 000 GNF", status: "active", joined: "21/02/2026", risk: "medium" },
  { name: "Sékou Touré", phone: "+224 621 99 88 77", wallet: "0 GNF", status: "pending", joined: "10/05/2026", risk: "low" },
];

export default function UsersAdmin() {
  const [filter, setFilter] = useState("Tous");
  return (
    <ModulePage module="users" title="Utilisateurs" subtitle="Recherche, KYC, suspensions et notes internes">
      <StatGrid items={[
        { label: "Total", value: "12 480", icon: Users },
        { label: "Actifs (30j)", value: "8 932", icon: UserCheck, tone: "text-emerald-600" },
        { label: "Suspendus", value: "47", icon: UserX, tone: "text-rose-600" },
        { label: "Risque élevé", value: "12", icon: ShieldAlert, tone: "text-amber-600" },
      ]} />
      <AdminToolbar placeholder="Rechercher par nom, téléphone, ID..." />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Actifs", "Suspendus", "En attente KYC", "Risque élevé"].map((f) => (
          <FilterChip key={f} label={f} active={filter === f} onClick={() => setFilter(f)} />
        ))}
      </div>
      <DataTable
        columns={["Nom", "Téléphone", "Wallet", "Statut", "Inscrit", "Risque", "Actions"]}
        rows={MOCK.map((u) => [
          <span className="font-medium">{u.name}</span>,
          u.phone, u.wallet, <StatusBadge status={u.status} />, u.joined, <StatusBadge status={u.risk} />,
          <div className="flex gap-1">
            <Button size="icon" variant="ghost" className="h-8 w-8"><Eye className="w-4 h-4" /></Button>
            <Button size="icon" variant="ghost" className="h-8 w-8"><Snowflake className="w-4 h-4" /></Button>
            <Button size="icon" variant="ghost" className="h-8 w-8"><MessageSquare className="w-4 h-4" /></Button>
          </div>,
        ])}
      />
    </ModulePage>
  );
}
