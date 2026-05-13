import { Card } from "@/components/ui/card";
import { Link } from "react-router-dom";
import { ModulePage } from "@/components/admin/ModulePage";
import {
  Users, Bike, Store, Coins, Wallet, ClipboardList, UtensilsCrossed,
  ShoppingBag, AlertTriangle, RefreshCw, Activity, CheckCircle2, ArrowRight,
} from "lucide-react";

const KPIS = [
  { label: "Utilisateurs", value: "12 480", icon: Users, to: "/admin/users", tone: "text-primary" },
  { label: "Chauffeurs en ligne", value: "342", icon: Bike, to: "/admin/drivers", tone: "text-emerald-600" },
  { label: "Marchands actifs", value: "186", icon: Store, to: "/admin/merchants", tone: "text-secondary" },
  { label: "Agents actifs", value: "47", icon: Coins, to: "/admin/vendors", tone: "text-amber-600" },
  { label: "Solde wallet total", value: "1.24 Mds GNF", icon: Wallet, to: "/admin/wallet", tone: "text-primary" },
  { label: "Courses du jour", value: "1 842", icon: ClipboardList, to: "/admin/orders", tone: "text-blue-600" },
  { label: "Commandes Repas", value: "612", icon: UtensilsCrossed, to: "/admin/repas", tone: "text-orange-600" },
  { label: "Annonces Marché", value: "3 921", icon: ShoppingBag, to: "/admin/marche", tone: "text-emerald-600" },
  { label: "Litiges en attente", value: "14", icon: AlertTriangle, to: "/admin/support", tone: "text-rose-600" },
  { label: "Remboursements", value: "5", icon: RefreshCw, to: "/admin/wallet", tone: "text-amber-600" },
];

const STATUS = [
  { label: "App", ok: true }, { label: "Wallet & paiements", ok: true },
  { label: "WhatsApp / SMS", ok: true }, { label: "Cartographie", ok: true }, { label: "Serveur", ok: true },
];

const FEED = [
  { t: "Il y a 2 min", text: "Chauffeur Amadou D. a accepté une course Moto", tone: "text-emerald-600" },
  { t: "Il y a 5 min", text: "Recharge agent Mariama K. — 250 000 GNF confirmée", tone: "text-primary" },
  { t: "Il y a 8 min", text: "Remboursement approuvé pour la course #CC-RD-9821", tone: "text-amber-600" },
  { t: "Il y a 12 min", text: "Nouveau marchand Repas validé : Le Damier", tone: "text-secondary" },
  { t: "Il y a 18 min", text: "Annonce Marché signalée — modération requise", tone: "text-rose-600" },
  { t: "Il y a 24 min", text: "Top-up agent Ibrahima S. — 1 000 000 GNF", tone: "text-primary" },
];

export default function AdminDashboard() {
  return (
    <ModulePage module="dashboard" title="Tableau de bord" subtitle="Vue commande de l'écosystème CHOP CHOP">
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {KPIS.map((k) => (
          <Link key={k.label} to={k.to} className="group">
            <Card className="p-4 transition-all hover:shadow-elevated hover:-translate-y-0.5 active:scale-[0.98] animate-fade-in cursor-pointer h-full">
              <div className="flex items-start justify-between">
                <k.icon className={`w-4 h-4 ${k.tone}`} />
                <ArrowRight className="w-3.5 h-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
              </div>
              <p className="text-xs text-muted-foreground mt-2">{k.label}</p>
              <p className="text-xl font-bold mt-1">{k.value}</p>
            </Card>
          </Link>
        ))}
      </div>

      <div className="grid md:grid-cols-3 gap-4">
        <Card className="p-5 md:col-span-2">
          <h2 className="font-semibold mb-4 flex items-center gap-2">
            <Activity className="w-4 h-4 text-primary" /> Activité récente
          </h2>
          <ul className="space-y-3">
            {FEED.map((f, i) => (
              <li key={i} className="flex items-start gap-3 text-sm">
                <span className={`w-2 h-2 mt-1.5 rounded-full ${f.tone.replace("text-", "bg-")}`} />
                <div className="flex-1 min-w-0">
                  <p className="truncate">{f.text}</p>
                  <p className="text-xs text-muted-foreground">{f.t}</p>
                </div>
              </li>
            ))}
          </ul>
        </Card>

        <Card className="p-5">
          <h2 className="font-semibold mb-4 flex items-center gap-2">
            <Activity className="w-4 h-4" /> Statut système
          </h2>
          <div className="space-y-2.5">
            {STATUS.map((s) => (
              <div key={s.label} className="flex items-center gap-2 text-sm">
                <CheckCircle2 className={`w-4 h-4 ${s.ok ? "text-emerald-500" : "text-destructive"}`} />
                <span className="flex-1">{s.label}</span>
                <span className="text-xs text-emerald-600">opérationnel</span>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </ModulePage>
  );
}
