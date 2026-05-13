import { Card } from "@/components/ui/card";
import { ModulePage } from "@/components/admin/ModulePage";
import {
  Users, Bike, Store, Coins, Wallet, ClipboardList,
  UtensilsCrossed, ShoppingBag, AlertTriangle, RefreshCw, Activity, CheckCircle2,
} from "lucide-react";

const KPIS = [
  { label: "Utilisateurs", value: "—", icon: Users },
  { label: "Chauffeurs en ligne", value: "—", icon: Bike },
  { label: "Marchands actifs", value: "—", icon: Store },
  { label: "Agents actifs", value: "—", icon: Coins },
  { label: "Solde wallet total", value: "—", icon: Wallet },
  { label: "Courses du jour", value: "—", icon: ClipboardList },
  { label: "Commandes Repas", value: "—", icon: UtensilsCrossed },
  { label: "Annonces Marché", value: "—", icon: ShoppingBag },
  { label: "Litiges en attente", value: "—", icon: AlertTriangle },
  { label: "Remboursements", value: "—", icon: RefreshCw },
];

const STATUS = [
  { label: "App", ok: true },
  { label: "Wallet & paiements", ok: true },
  { label: "WhatsApp / SMS", ok: true },
  { label: "Cartographie", ok: true },
  { label: "Serveur", ok: true },
];

export default function AdminDashboard() {
  return (
    <ModulePage module="dashboard" title="Tableau de bord" subtitle="Vue commande de l'écosystème CHOP CHOP">
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {KPIS.map((k) => (
          <Card key={k.label} className="p-4">
            <k.icon className="w-4 h-4 text-muted-foreground" />
            <p className="text-xs text-muted-foreground mt-2">{k.label}</p>
            <p className="text-xl font-bold mt-1">{k.value}</p>
          </Card>
        ))}
      </div>
      <Card className="p-5">
        <h2 className="font-semibold mb-3 flex items-center gap-2">
          <Activity className="w-4 h-4" /> Statut système
        </h2>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
          {STATUS.map((s) => (
            <div key={s.label} className="flex items-center gap-2 text-sm">
              <CheckCircle2 className={`w-4 h-4 ${s.ok ? "text-emerald-500" : "text-destructive"}`} />
              {s.label}
            </div>
          ))}
        </div>
      </Card>
    </ModulePage>
  );
}