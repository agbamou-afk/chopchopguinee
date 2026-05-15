import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { Users, Timer, BellRing } from "lucide-react";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { useDriverSession } from "@/contexts/DriverSessionContext";
import { IncomingRequestPopup } from "@/components/driver/IncomingRequestPopup";
import { DriverHotspotsCard } from "@/components/driver/DriverHotspotsCard";

export function DriverOrdersView() {
  const { queue, current, currentExpiresAt, accept, decline, showCurrent, isOnline, activeTrip } = useDriverSession();
  const displayedRequest = !activeTrip ? current ?? queue[0] ?? null : null;
  const offerTimeoutSec = currentExpiresAt
    ? Math.max(1, Math.ceil((new Date(currentExpiresAt).getTime() - Date.now()) / 1000))
    : 20;

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader title="Mes courses" subtitle="Demandes entrantes et course active" />

      <div className="mt-4 mb-2">
        <LiveStrip
          stats={[
            { icon: Users, label: `${queue.length} demande${queue.length > 1 ? "s" : ""} proche${queue.length > 1 ? "s" : ""}`, bg: "bg-primary/10", tone: "text-primary" },
            { icon: Timer, label: isOnline ? "En ligne" : "Hors ligne", bg: "bg-secondary/20", tone: "text-foreground" },
          ]}
        />
      </div>

      {/* Pending offers banner — only when no popup is currently displayed */}
      {isOnline && !displayedRequest && queue.length > 0 && (
        <div className="px-4 mt-2">
          <button
            onClick={showCurrent}
            className="w-full flex items-center gap-3 p-3 rounded-2xl bg-primary/5 border border-primary/30 text-left hover:bg-primary/10 transition"
          >
            <div className="p-2 rounded-xl bg-primary/15">
              <BellRing className="w-4 h-4 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-foreground">
                {queue.length} demande{queue.length > 1 ? "s" : ""} en attente
              </p>
              <p className="text-xs text-muted-foreground">Touchez pour voir la suivante</p>
            </div>
          </button>
        </div>
      )}

      {activeTrip ? (
        <div className="px-4 pb-28">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-card rounded-2xl shadow-elevated overflow-hidden border border-primary/30"
          >
            <div className="gradient-wallet px-4 py-3">
              <div className="flex items-center justify-between text-primary-foreground">
                <span className="font-bold">Course active</span>
                <span className="text-xs opacity-80">Navigation ouverte</span>
              </div>
            </div>

            <div className="p-4 space-y-4">
              <div className="space-y-4">
                <div className="flex items-start gap-3">
                  <div className="mt-1">
                    <div className="w-3 h-3 rounded-full bg-primary" />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs text-muted-foreground">Point de départ</p>
                    <p className="font-medium text-foreground">{activeTrip.pickup}</p>
                  </div>
                </div>
                <div className="flex items-start gap-3">
                  <div className="mt-1">
                    <div className="w-3 h-3 rounded-full bg-secondary" />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs text-muted-foreground">Destination</p>
                    <p className="font-medium text-foreground">{activeTrip.destination}</p>
                  </div>
                </div>
              </div>

              <div className="flex items-center justify-between py-3 px-4 bg-muted rounded-xl mb-4">
                <span className="text-muted-foreground">Montant estimé</span>
                <span className="text-xl font-bold text-foreground">
                  {formatGNF(activeTrip.estimatedPrice)}
                </span>
              </div>
            </div>
          </motion.div>
        </div>
      ) : (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="px-4 mt-3 pb-28 flex flex-col"
          style={{ minHeight: "calc(100dvh - 220px)" }}
        >
          <DriverHotspotsCard isOnline={isOnline} full />
        </motion.div>
      )}

      {/* Bottom-sheet popup lives in the Courses tab only */}
      <IncomingRequestPopup
        request={displayedRequest}
        onAccept={accept}
        onDecline={decline}
        timeoutSec={offerTimeoutSec}
      />
    </div>
  );
}
