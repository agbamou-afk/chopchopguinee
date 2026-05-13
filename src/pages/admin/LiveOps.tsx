import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge, FilterChip } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Activity, Bike, Package, Clock } from "lucide-react";
import { useState } from "react";
import { AdminLiveOpsMap } from "@/components/admin/AdminLiveOpsMap";

const RIDES = [
  { id: "CC-RD-9881", driver: "Amadou D.", from: "Kipé", to: "Kaloum", eta: "8 min", status: "active" },
  { id: "CC-RD-9882", driver: "Sékou C.", from: "Madina", to: "Ratoma", eta: "12 min", status: "active" },
  { id: "CC-RD-9883", driver: "—", from: "Hamdallaye", to: "Coyah", eta: "—", status: "pending" },
  { id: "CC-LV-7720", driver: "Fatou T.", from: "Le Damier", to: "Dixinn", eta: "5 min", status: "active" },
  { id: "CC-LV-7721", driver: "Ibrahima B.", from: "Pharmacie Niger", to: "Lambanyi", eta: "Retard +9 min", status: "escalated" },
];

export default function LiveOps() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="live_ops" title="Live Operations" subtitle="Centre de commande en temps réel">
      <StatGrid items={[
        { label: "Courses actives", value: "184", icon: Bike, tone: "text-primary" },
        { label: "Livraisons en cours", value: "62", icon: Package, tone: "text-emerald-600" },
        { label: "En attente d'accept.", value: "9", icon: Clock, tone: "text-amber-600" },
        { label: "Retards", value: "3", icon: Activity, tone: "text-rose-600" },
      ]} />
      <AdminLiveOpsMap variant="moto" />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Moto", "TokTok", "Envoyer", "Repas", "Retards"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <div className="space-y-2">
        {RIDES.map((r) => (
          <Card key={r.id} className="p-3 flex items-center gap-3 hover:shadow-soft transition-all">
            <div className="w-9 h-9 rounded-xl gradient-primary flex items-center justify-center shrink-0">
              <Bike className="w-4 h-4 text-primary-foreground" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <p className="font-medium text-sm">{r.id}</p>
                <StatusBadge status={r.status} />
              </div>
              <p className="text-xs text-muted-foreground truncate">{r.from} → {r.to} · {r.driver}</p>
            </div>
            <div className="text-right shrink-0">
              <p className="text-xs text-muted-foreground">ETA</p>
              <p className="text-sm font-semibold">{r.eta}</p>
            </div>
          </Card>
        ))}
      </div>
    </ModulePage>
  );
}
