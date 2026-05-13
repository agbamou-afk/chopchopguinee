import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { TrendingUp, Calendar, Download, ChevronRight, Bike, UtensilsCrossed, Package, Wallet, ShieldCheck, Timer } from "lucide-react";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";

const weeklyData = [
  { day: "Lun", amount: 85000, rides: 5 },
  { day: "Mar", amount: 120000, rides: 7 },
  { day: "Mer", amount: 95000, rides: 6 },
  { day: "Jeu", amount: 150000, rides: 9 },
  { day: "Ven", amount: 180000, rides: 11 },
  { day: "Sam", amount: 220000, rides: 14 },
  { day: "Dim", amount: 185000, rides: 12 },
];

const recentEarnings = [
  {
    id: 1,
    type: "ride" as const,
    description: "Course Moto - Madina → Kipé",
    amount: 15000,
    time: "14:30",
    tip: 2000,
  },
  {
    id: 2,
    type: "food" as const,
    description: "Livraison repas - Chez Mama",
    amount: 8000,
    time: "12:45",
    tip: 0,
  },
  {
    id: 3,
    type: "delivery" as const,
    description: "Livraison colis - Marché CHOP CHOP",
    amount: 12000,
    time: "10:15",
    tip: 3000,
  },
  {
    id: 4,
    type: "ride" as const,
    description: "Course Moto - Ratoma → Taouyah",
    amount: 20000,
    time: "09:00",
    tip: 0,
  },
];

const typeIcons = {
  ride: Bike,
  food: UtensilsCrossed,
  delivery: Package,
};

export function DriverEarningsView() {
  const formatMoney = (amount: number) =>
    formatGNF(amount);

  const totalWeekly = weeklyData.reduce((sum, d) => sum + d.amount, 0);
  const maxAmount = Math.max(...weeklyData.map((d) => d.amount));

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader
        title="Mes gains"
        subtitle="Suivi des revenus et pourboires"
        right={
          <button aria-label="Calendrier" className="w-10 h-10 rounded-full bg-card border border-border/60 flex items-center justify-center hover:bg-muted">
            <Calendar className="w-5 h-5 text-foreground" />
          </button>
        }
      />

      {/* Wallet-style total card */}
      <div className="px-4 mt-4">
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="gradient-wallet rounded-3xl p-5 text-primary-foreground ring-glow-primary relative overflow-hidden"
        >
          <div className="pointer-events-none absolute -top-12 -right-10 w-44 h-44 rounded-full bg-white/10 blur-2xl" aria-hidden />
          <div className="flex items-center gap-2 opacity-90">
            <Wallet className="w-4 h-4" />
            <p className="text-[11px] uppercase tracking-wider">Total cette semaine</p>
          </div>
          <h2 className="text-3xl font-extrabold mt-1 leading-none">{formatMoney(totalWeekly)}</h2>
          <div className="flex items-center gap-2 mt-2 text-[12px] opacity-90">
            <TrendingUp className="w-4 h-4" />
            <span>+18 % vs semaine dernière</span>
          </div>

          {/* Weekly chart inside the hero */}
          <div className="mt-4 flex items-end justify-between gap-2 h-20">
            {weeklyData.map((data, index) => (
              <div key={data.day} className="flex-1 flex flex-col items-center gap-1">
                <motion.div
                  initial={{ height: 0 }}
                  animate={{ height: `${(data.amount / maxAmount) * 100}%` }}
                  transition={{ delay: index * 0.05, duration: 0.5 }}
                  className="w-full bg-white/40 rounded-t-md min-h-[8px]"
                />
                <span className="text-[10px] opacity-80">{data.day}</span>
              </div>
            ))}
          </div>
        </motion.div>
      </div>

      {/* Live strip */}
      <div className="mt-4">
        <LiveStrip
          stats={[
            { icon: TrendingUp, label: "+18% cette semaine", bg: "bg-success/10", tone: "text-success" },
            { icon: Timer, label: "42h en ligne", bg: "bg-primary/10", tone: "text-primary" },
            { icon: ShieldCheck, label: "Versement sous 24h", bg: "bg-secondary/20", tone: "text-foreground" },
          ]}
        />
      </div>

      {/* Quick stats */}
      <div className="px-4 mt-4 mb-6">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-card border border-border/60 grid grid-cols-3 gap-4"
        >
          <div className="text-center">
            <p className="text-2xl font-bold text-foreground">64</p>
            <p className="text-xs text-muted-foreground">Courses</p>
          </div>
          <div className="text-center border-x border-border">
            <p className="text-2xl font-bold text-foreground">42h</p>
            <p className="text-xs text-muted-foreground">En ligne</p>
          </div>
          <div className="text-center">
            <p className="text-2xl font-bold text-success">{formatMoney(15000)}</p>
            <p className="text-xs text-muted-foreground">Pourboires</p>
          </div>
        </motion.div>
      </div>

      {/* Actions */}
      <div className="px-4 mb-6">
        <div className="grid grid-cols-2 gap-3">
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className="flex items-center justify-center gap-2 py-4 gradient-wallet text-primary-foreground rounded-2xl font-semibold ring-glow-primary"
          >
            <Download className="w-5 h-5" />
            Retirer
          </motion.button>
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className="flex items-center justify-center gap-2 py-4 bg-card border border-border text-foreground rounded-2xl font-semibold"
          >
            Historique
            <ChevronRight className="w-5 h-5" />
          </motion.button>
        </div>
      </div>

      {/* Recent earnings */}
      <div className="px-4 pb-28">
        <h2 className="text-lg font-bold text-foreground mb-4">Gains récents</h2>
        <div className="space-y-3">
          {recentEarnings.map((earning, index) => {
            const Icon = typeIcons[earning.type];
            return (
              <motion.div
                key={earning.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: index * 0.05 }}
                className="bg-card rounded-2xl p-4 shadow-card flex items-center gap-3"
              >
                <div className="p-2 rounded-xl bg-primary/10">
                  <Icon className="w-5 h-5 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="font-medium text-foreground text-sm">
                    {earning.description}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    Aujourd'hui, {earning.time}
                  </p>
                </div>
                <div className="text-right">
                  <p className="font-semibold text-success">
                    +{formatMoney(earning.amount)}
                  </p>
                  {earning.tip > 0 && (
                    <p className="text-xs text-secondary">
                      +{formatMoney(earning.tip)} pourboire
                    </p>
                  )}
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
