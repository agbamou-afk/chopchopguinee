import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge, FilterChip, AdminToolbar } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { LifeBuoy, Clock, CheckCircle2, AlertTriangle } from "lucide-react";
import { useState } from "react";

const TICKETS = [
  { id: "T-2188", user: "Mariama D.", subject: "Course non terminée", assignee: "—", status: "open", t: "Il y a 12 min" },
  { id: "T-2187", user: "Amadou B.", subject: "Recharge non créditée", assignee: "Aïcha", status: "investigating", t: "Il y a 32 min" },
  { id: "T-2186", user: "Sékou T.", subject: "Demande de remboursement", assignee: "Mamadou", status: "escalated", t: "Il y a 1 h" },
  { id: "T-2185", user: "Fatou C.", subject: "Plainte chauffeur", assignee: "Aïcha", status: "resolved", t: "Il y a 3 h" },
];

export default function SupportAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="support" title="Support & Litiges" subtitle="Tickets, conversations et escalades">
      <StatGrid items={[
        { label: "Ouverts", value: "14", icon: LifeBuoy, tone: "text-amber-600" },
        { label: "En cours", value: "23", icon: Clock, tone: "text-blue-600" },
        { label: "Résolus (24h)", value: "47", icon: CheckCircle2, tone: "text-emerald-600" },
        { label: "Escaladés", value: "3", icon: AlertTriangle, tone: "text-rose-600" },
      ]} />
      <AdminToolbar placeholder="Rechercher ticket, utilisateur..." />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Ouverts", "Investigation", "Escaladés", "Résolus"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <div className="space-y-2">
        {TICKETS.map((t) => (
          <Card key={t.id} className="p-4 hover:shadow-soft transition-all">
            <div className="flex items-start justify-between gap-3">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-semibold text-sm">{t.id}</span>
                  <StatusBadge status={t.status} />
                </div>
                <p className="text-sm font-medium truncate">{t.subject}</p>
                <p className="text-xs text-muted-foreground">{t.user} · Assigné: {t.assignee} · {t.t}</p>
              </div>
              <div className="flex flex-col gap-1 shrink-0">
                <Button size="sm" variant="outline">Ouvrir</Button>
                <Button size="sm" variant="ghost">Rembourser</Button>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </ModulePage>
  );
}
