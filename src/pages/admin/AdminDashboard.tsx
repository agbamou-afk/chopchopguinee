import { Link } from "react-router-dom";
import { ModulePage } from "@/components/admin/ModulePage";
import {
  Users, Bike, Store, Coins, Wallet, ClipboardList, UtensilsCrossed,
  ShoppingBag, AlertTriangle, RefreshCw, Activity, ArrowRight,
} from "lucide-react";

const KPIS = [
  { label: "Utilisateurs",        value: "12 480",       delta: "+1.4%", icon: Users,           to: "/admin/users" },
  { label: "Chauffeurs en ligne", value: "342",          delta: "+12",   icon: Bike,            to: "/admin/drivers" },
  { label: "Marchands actifs",    value: "186",          delta: "+3",    icon: Store,           to: "/admin/merchants" },
  { label: "Agents actifs",       value: "47",           delta: "0",     icon: Coins,           to: "/admin/vendors" },
  { label: "Solde wallet total",  value: "1.24 Mds GNF", delta: "+2.1%", icon: Wallet,          to: "/admin/wallet" },
  { label: "Courses du jour",     value: "1 842",        delta: "+5.6%", icon: ClipboardList,   to: "/admin/orders" },
  { label: "Commandes Repas",     value: "612",          delta: "+8.2%", icon: UtensilsCrossed, to: "/admin/repas" },
  { label: "Annonces Marché",     value: "3 921",        delta: "+0.9%", icon: ShoppingBag,     to: "/admin/marche" },
  { label: "Litiges en attente",  value: "14",           delta: "−2",    icon: AlertTriangle,   to: "/admin/support" },
  { label: "Remboursements",      value: "5",            delta: "+1",    icon: RefreshCw,       to: "/admin/wallet" },
];

const STATUS = [
  { label: "App", ok: true }, { label: "Wallet & paiements", ok: true },
  { label: "WhatsApp / SMS", ok: true }, { label: "Cartographie", ok: true }, { label: "Serveur", ok: true },
];

const FEED = [
  { t: "+2m",  text: "Chauffeur Amadou D. a accepté une course Moto",      dot: "bg-primary" },
  { t: "+5m",  text: "Recharge agent Mariama K. — 250 000 GNF confirmée",  dot: "bg-primary" },
  { t: "+8m",  text: "Remboursement approuvé pour la course #CC-RD-9821",  dot: "bg-secondary" },
  { t: "+12m", text: "Nouveau marchand Repas validé : Le Damier",          dot: "bg-primary" },
  { t: "+18m", text: "Annonce Marché signalée — modération requise",       dot: "bg-destructive" },
  { t: "+24m", text: "Top-up agent Ibrahima S. — 1 000 000 GNF",           dot: "bg-primary" },
];

export default function AdminDashboard() {
  return (
    <ModulePage module="dashboard" title="Tableau de bord" subtitle="Vue commande de l'écosystème CHOP CHOP">
      <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
        {KPIS.map((k) => {
          const negative = k.delta.startsWith("−");
          return (
            <Link key={k.label} to={k.to} className="group">
              <div className="admin-card p-3 h-full transition-colors hover:border-primary/40">
                <div className="flex items-center justify-between">
                  <span className="admin-eyebrow truncate">{k.label}</span>
                  <k.icon className="w-3.5 h-3.5 text-muted-foreground/70 group-hover:text-primary transition-colors" />
                </div>
                <p className="text-[18px] font-semibold mt-1.5 tabular-nums tracking-tight">{k.value}</p>
                <div className="flex items-center justify-between mt-1">
                  <span className={`font-mono text-[10px] tabular-nums ${negative ? "text-destructive" : "text-emerald-700/80"}`}>
                    {k.delta} · 24h
                  </span>
                  <ArrowRight className="w-3 h-3 text-muted-foreground/50 opacity-0 group-hover:opacity-100 transition-opacity" />
                </div>
              </div>
            </Link>
          );
        })}
      </div>

      <div className="grid md:grid-cols-3 gap-3">
        <div className="admin-card p-4 md:col-span-2">
          <div className="flex items-center justify-between mb-3">
            <h2 className="admin-eyebrow flex items-center gap-1.5">
              <Activity className="w-3 h-3" /> Activité récente
            </h2>
            <span className="font-mono text-[10px] text-muted-foreground/70">live · 24h</span>
          </div>
          <ul className="divide-y divide-border/50">
            {FEED.map((f, i) => (
              <li key={i} className="flex items-center gap-3 py-1.5 text-[13px]">
                <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${f.dot}`} />
                <p className="flex-1 min-w-0 truncate">{f.text}</p>
                <span className="font-mono text-[10px] text-muted-foreground/70 tabular-nums">{f.t}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="admin-card p-4">
          <h2 className="admin-eyebrow mb-3">Statut système</h2>
          <div className="space-y-1.5">
            {STATUS.map((s) => (
              <div key={s.label} className="flex items-center gap-2 text-[13px]">
                <span className="flex-1 truncate text-foreground/80">{s.label}</span>
                <span className={`chip-status ${s.ok ? "chip-ok" : "chip-err"}`}>
                  {s.ok ? "ok" : "down"}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </ModulePage>
  );
}
