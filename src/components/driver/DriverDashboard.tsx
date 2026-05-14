import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { TrendingUp, DollarSign, Clock, CheckCircle, XCircle, Car } from "lucide-react";

interface DriverDashboardProps {
  todayEarnings: number;
  weeklyEarnings: number;
  completedRides: number;
  onlineHours: number;
  acceptRate?: number;
}

export function DriverDashboard({
  todayEarnings,
  weeklyEarnings,
  completedRides,
  onlineHours,
}: DriverDashboardProps) {
  const formatMoney = (amount: number) =>
    formatGNF(amount);

  return (
    <div className="space-y-4">
      {/* Today's earnings card */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="gradient-primary rounded-2xl p-5 text-primary-foreground"
      >
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className="text-sm opacity-80">Gains du jour</p>
            <h2 className="text-3xl font-bold mt-1">
              {formatMoney(todayEarnings)}
            </h2>
          </div>
          <div className="p-3 bg-white/20 rounded-xl">
            <TrendingUp className="w-6 h-6" />
          </div>
        </div>
        <div className="flex items-center gap-2 text-sm">
          <span className="bg-white/20 px-2 py-1 rounded-full">
            +15% vs hier
          </span>
        </div>
      </motion.div>

      {/* Stats grid */}
      <div className="grid grid-cols-2 gap-3">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="bg-card rounded-2xl p-4 shadow-card"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="p-2 rounded-lg bg-primary/10">
              <DollarSign className="w-4 h-4 text-primary" />
            </div>
            <span className="text-xs text-muted-foreground">Cette semaine</span>
          </div>
          <p className="text-lg font-bold text-foreground">
            {formatMoney(weeklyEarnings)}
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15 }}
          className="bg-card rounded-2xl p-4 shadow-card"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="p-2 rounded-lg bg-success/10">
              <CheckCircle className="w-4 h-4 text-success" />
            </div>
            <span className="text-xs text-muted-foreground">Courses</span>
          </div>
          <p className="text-lg font-bold text-foreground">{completedRides}</p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="bg-card rounded-2xl p-4 shadow-card"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="p-2 rounded-lg bg-secondary/10">
              <Clock className="w-4 h-4 text-secondary" />
            </div>
            <span className="text-xs text-muted-foreground">Heures en ligne</span>
          </div>
          <p className="text-lg font-bold text-foreground">{onlineHours}h</p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.25 }}
          className="bg-card rounded-2xl p-4 shadow-card"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="p-2 rounded-lg bg-primary/10">
              <Car className="w-4 h-4 text-primary" />
            </div>
            <span className="text-xs text-muted-foreground">Taux acceptation</span>
          </div>
          <p className="text-lg font-bold text-foreground">94%</p>
        </motion.div>
      </div>
    </div>
  );
}
