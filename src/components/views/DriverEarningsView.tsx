import { motion } from "framer-motion";
import { TrendingUp, Calendar, Download, ChevronRight, Bike, UtensilsCrossed, Package } from "lucide-react";

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
    description: "Livraison colis - Marché Chop Chop",
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
    new Intl.NumberFormat("fr-GN").format(amount);

  const totalWeekly = weeklyData.reduce((sum, d) => sum + d.amount, 0);
  const maxAmount = Math.max(...weeklyData.map((d) => d.amount));

  return (
    <div className="max-w-md mx-auto">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="gradient-hero text-primary-foreground px-4 pt-6 pb-8 rounded-b-3xl"
      >
        <div className="flex items-center justify-between mb-4">
          <h1 className="text-xl font-bold">Mes gains</h1>
          <button className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition-colors">
            <Calendar className="w-5 h-5" />
          </button>
        </div>

        <div className="text-center mb-6">
          <p className="text-sm opacity-80">Total cette semaine</p>
          <h2 className="text-4xl font-bold mt-2">{formatMoney(totalWeekly)} GNF</h2>
          <div className="flex items-center justify-center gap-2 mt-2">
            <TrendingUp className="w-4 h-4" />
            <span className="text-sm">+18% vs semaine dernière</span>
          </div>
        </div>

        {/* Weekly chart */}
        <div className="flex items-end justify-between gap-2 h-24 px-2">
          {weeklyData.map((data, index) => (
            <div key={data.day} className="flex-1 flex flex-col items-center gap-1">
              <motion.div
                initial={{ height: 0 }}
                animate={{ height: `${(data.amount / maxAmount) * 100}%` }}
                transition={{ delay: index * 0.05, duration: 0.5 }}
                className="w-full bg-white/30 rounded-t-md min-h-[8px]"
              />
              <span className="text-xs opacity-80">{data.day}</span>
            </div>
          ))}
        </div>
      </motion.header>

      {/* Quick stats */}
      <div className="px-4 -mt-4 mb-6">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-elevated grid grid-cols-3 gap-4"
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
            className="flex items-center justify-center gap-2 py-4 bg-primary text-primary-foreground rounded-2xl font-medium"
          >
            <Download className="w-5 h-5" />
            Retirer
          </motion.button>
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className="flex items-center justify-center gap-2 py-4 bg-muted text-foreground rounded-2xl font-medium"
          >
            Historique
            <ChevronRight className="w-5 h-5" />
          </motion.button>
        </div>
      </div>

      {/* Recent earnings */}
      <div className="px-4 pb-6">
        <h2 className="text-lg font-semibold text-foreground mb-4">Gains récents</h2>
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
                    +{formatMoney(earning.amount)} GNF
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
