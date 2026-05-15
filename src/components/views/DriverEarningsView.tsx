import { motion } from "framer-motion";
import { useEffect, useState } from "react";
import { formatGNF } from "@/lib/format";
import { TrendingUp, Calendar, Download, ChevronRight, Bike, Wallet, ShieldCheck, AlertTriangle } from "lucide-react";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { useDriverEarnings } from "@/hooks/useDriverEarnings";
import { useWallet } from "@/hooks/useWallet";
import { toast } from "sonner";
import { ActivityTimeline } from "@/components/activity/ActivityTimeline";
import { useActivityFeed } from "@/lib/activity/useActivityFeed";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export function DriverEarningsView() {
  const e = useDriverEarnings();
  const { available: walletBalance } = useWallet("driver");
  // Driver-perspective activity: completed rides (with earning amounts),
  // CHOPWallet credits, payouts, refunds. Replaces the legacy "Courses
  // récentes" list with the unified ecosystem timeline.
  const driverFeed = useActivityFeed("driver");
  useEffect(() => {
    if (!driverFeed.loading) {
      Analytics.track("driver.activity.viewed", {
        metadata: { count: driverFeed.items.length },
      });
    }
    // Only fire once per mount when the feed first resolves.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driverFeed.loading]);
  const [_settling] = useState(false);
  void _settling;
  const formatMoney = formatGNF;
  const maxAmount = Math.max(1, ...e.weeklyBuckets.map((d) => d.amount));
  const cashOverLimit = e.debtLimitGnf > 0 && e.cashDebtGnf >= e.debtLimitGnf;

  const handleSettleInfo = () => {
    toast.info(
      e.cashDebtGnf > 0
        ? `Déposez ${formatMoney(e.cashDebtGnf)} chez un agent CHOP CHOP. Le règlement sera enregistré sous 24 h.`
        : "Aucune commission cash à régler.",
    );
  };

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader
        title="Mes gains"
        subtitle="Revenus, commission cash et versements"
        right={
          <button aria-label="Calendrier" className="w-10 h-10 rounded-full bg-card border border-border/60 flex items-center justify-center hover:bg-muted">
            <Calendar className="w-5 h-5 text-foreground" />
          </button>
        }
      />

      {cashOverLimit && (
        <div className="px-4 mt-3">
          <div className="rounded-2xl border border-destructive/40 bg-destructive/5 p-3 flex items-start gap-2">
            <AlertTriangle className="w-4 h-4 text-destructive mt-0.5 flex-shrink-0" />
            <p className="text-xs text-foreground">
              Limite de cash atteinte ({formatMoney(e.debtLimitGnf)}). Vous ne pourrez pas repasser en ligne tant que la commission n'est pas réglée.
            </p>
          </div>
        </div>
      )}

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
            <p className="text-[11px] uppercase tracking-wider">Gains cette semaine</p>
          </div>
          <h2 className="text-3xl font-extrabold mt-1 leading-none">
            {e.loading ? "…" : formatMoney(e.weekGnf)}
          </h2>
          <div className="flex items-center gap-2 mt-2 text-[12px] opacity-90">
            <TrendingUp className="w-4 h-4" />
            <span>Aujourd'hui : {formatMoney(e.todayGnf)} · {e.completedToday} course{e.completedToday > 1 ? "s" : ""}</span>
          </div>

          <div className="mt-4 flex items-end justify-between gap-2 h-20">
            {e.weeklyBuckets.map((data, index) => (
              <div key={`${data.day}-${index}`} className="flex-1 flex flex-col items-center gap-1">
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

      <div className="mt-4">
        <LiveStrip
          stats={[
            { icon: Wallet, label: `Solde ${formatMoney(walletBalance ?? 0)}`, bg: "bg-primary/10", tone: "text-primary" },
            { icon: Bike, label: `${e.completedWeek} courses`, bg: "bg-success/10", tone: "text-success" },
            { icon: ShieldCheck, label: "Versement sous 24h", bg: "bg-secondary/20", tone: "text-foreground" },
          ]}
        />
      </div>

      {/* Cash + commission */}
      <div className="px-4 mt-4 mb-6">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-card border border-border/60 grid grid-cols-3 gap-2"
        >
          <div className="text-center">
            <p className="text-base font-bold text-foreground">{formatMoney(e.cashCollectedWeek)}</p>
            <p className="text-[10px] text-muted-foreground mt-0.5 uppercase tracking-wide">Cash 7 j</p>
          </div>
          <div className="text-center border-x border-border">
            <p className={`text-base font-bold ${e.commissionDueWeek > 0 ? "text-destructive" : "text-foreground"}`}>
              {formatMoney(e.commissionDueWeek)}
            </p>
            <p className="text-[10px] text-muted-foreground mt-0.5 uppercase tracking-wide">Commission</p>
          </div>
          <div className="text-center">
            <p className={`text-base font-bold ${e.cashDebtGnf > 0 ? "text-destructive" : "text-success"}`}>
              {formatMoney(e.cashDebtGnf)}
            </p>
            <p className="text-[10px] text-muted-foreground mt-0.5 uppercase tracking-wide">Solde dû</p>
          </div>
        </motion.div>
      </div>

      {/* Actions */}
      <div className="px-4 mb-6">
        <div className="grid grid-cols-2 gap-3">
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={handleSettleInfo}
            disabled={e.cashDebtGnf <= 0}
            className="flex items-center justify-center gap-2 py-4 gradient-wallet text-primary-foreground rounded-2xl font-semibold ring-glow-primary disabled:opacity-50 text-sm"
          >
            <Wallet className="w-5 h-5" />
            {e.cashDebtGnf > 0 ? "Régler" : "Aucune dette"}
          </motion.button>
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className="flex items-center justify-center gap-2 py-4 bg-card border border-border text-foreground rounded-2xl font-semibold text-sm"
          >
            <Download className="w-4 h-4" />
            Versement
            <ChevronRight className="w-4 h-4" />
          </motion.button>
        </div>
      </div>

      {/* Unified driver activity — completed rides with earnings, wallet
          credits, payouts. One operational history instead of a siloed list. */}
      <div className="px-3 pb-28">
        <h2 className="text-lg font-bold text-foreground mb-3 px-1">Activité opérationnelle</h2>
        <ActivityTimeline items={driverFeed.items} loading={driverFeed.loading} />
      </div>
    </div>
  );
}
