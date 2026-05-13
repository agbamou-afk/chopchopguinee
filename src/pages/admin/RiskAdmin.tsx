import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, FilterChip, StatusBadge } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ShieldAlert, AlertTriangle, Activity, Snowflake } from "lucide-react";
import { useState } from "react";

const ALERTS = [
  { id: "RX-441", who: "Agent Ibrahima S.", reason: "12 top-ups identiques en 1h", severity: "high" },
  { id: "RX-440", who: "Utilisateur Mamadou T.", reason: "5 demandes de remboursement / 7j", severity: "medium" },
  { id: "RX-439", who: "Chauffeur Sékou C.", reason: "Annulations répétées (8/12)", severity: "medium" },
  { id: "RX-438", who: "Annonce ML-9712", reason: "Photos signalées dupliquées", severity: "low" },
];

export default function RiskAdmin() {
  const [f, setF] = useState("Tous");
  return (
    <ModulePage module="risk" title="Fraude & Risque" subtitle="Détection d'anomalies et actions rapides">
      <StatGrid items={[
        { label: "Alertes ouvertes", value: "18", icon: ShieldAlert, tone: "text-rose-600" },
        { label: "Risque élevé", value: "5", icon: AlertTriangle, tone: "text-rose-600" },
        { label: "Actions 24h", value: "12", icon: Activity, tone: "text-primary" },
        { label: "Comptes gelés", value: "7", icon: Snowflake, tone: "text-blue-600" },
      ]} />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Wallet", "Agents", "Chauffeurs", "Marketplace"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <div className="space-y-2">
        {ALERTS.map((a) => (
          <Card key={a.id} className={`p-4 border-l-4 ${a.severity === "high" ? "border-l-rose-500" : a.severity === "medium" ? "border-l-amber-500" : "border-l-emerald-500"}`}>
            <div className="flex items-start justify-between gap-3">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-mono text-xs text-muted-foreground">{a.id}</span>
                  <StatusBadge status={a.severity} />
                </div>
                <p className="font-medium text-sm">{a.who}</p>
                <p className="text-xs text-muted-foreground">{a.reason}</p>
              </div>
              <div className="flex gap-1 shrink-0">
                <Button size="sm" variant="outline">Enquêter</Button>
                <Button size="sm" variant="ghost" className="text-rose-600">Geler</Button>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </ModulePage>
  );
}
