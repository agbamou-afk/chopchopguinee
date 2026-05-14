import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { Clock, Users, Timer, BellRing } from "lucide-react";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { useDriverSession } from "@/contexts/DriverSessionContext";
import { IncomingRequestPopup } from "@/components/driver/IncomingRequestPopup";

export function DriverOrdersView() {
  const { queue, current, accept, decline, showCurrent, isOnline, activeTrip } = useDriverSession();

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
      {isOnline && !current && !activeTrip && queue.length > 0 && (
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

      {activeOrder ? (
        <div className="px-4 pb-28">
          {/* Active order card */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-card rounded-2xl shadow-elevated overflow-hidden"
          >
            {/* Status banner */}
            <div className={`${activeOrder.status === "arrived" ? "bg-success" : "gradient-wallet"} px-4 py-3`}>
              <div className="flex items-center justify-between text-primary-foreground">
                <span className="font-bold">{statusInfo[activeOrder.status].label}</span>
                <span className="text-xs opacity-80">{activeOrder.id}</span>
              </div>
            </div>

            <div className="p-4">
              {/* Customer info */}
              <div className="flex items-center justify-between mb-4 pb-4 border-b border-border">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center text-lg font-bold text-foreground">
                    {activeOrder.customerName.split(" ").map(n => n[0]).join("")}
                  </div>
                  <div>
                    <p className="font-semibold text-foreground">{activeOrder.customerName}</p>
                    <p className="text-sm text-muted-foreground">{activeOrder.customerPhone}</p>
                  </div>
                </div>
                <div className="flex gap-2">
                  <button className="p-2 rounded-full bg-primary/10 hover:bg-primary/20 transition-colors">
                    <Phone className="w-5 h-5 text-primary" />
                  </button>
                  <button className="p-2 rounded-full bg-primary/10 hover:bg-primary/20 transition-colors">
                    <MessageCircle className="w-5 h-5 text-primary" />
                  </button>
                </div>
              </div>

              {/* Route */}
              <div className="space-y-4 mb-4">
                <div className="flex items-start gap-3">
                  <div className="mt-1">
                    <div className="w-3 h-3 rounded-full bg-primary" />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs text-muted-foreground">Point de départ</p>
                    <p className="font-medium text-foreground">{activeOrder.pickup}</p>
                  </div>
                  <button className="p-2 rounded-lg bg-muted hover:bg-muted/80 transition-colors">
                    <Navigation className="w-4 h-4 text-muted-foreground" />
                  </button>
                </div>
                <div className="flex items-start gap-3">
                  <div className="mt-1">
                    <div className="w-3 h-3 rounded-full bg-secondary" />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs text-muted-foreground">Destination</p>
                    <p className="font-medium text-foreground">{activeOrder.destination}</p>
                  </div>
                  <button className="p-2 rounded-lg bg-muted hover:bg-muted/80 transition-colors">
                    <Navigation className="w-4 h-4 text-muted-foreground" />
                  </button>
                </div>
              </div>

              {/* Price */}
              <div className="flex items-center justify-between py-3 px-4 bg-muted rounded-xl mb-4">
                <span className="text-muted-foreground">Montant estimé</span>
                <span className="text-xl font-bold text-foreground">
                  {formatMoney(activeOrder.estimatedPrice)}
                </span>
              </div>

              {/* Action button */}
              <Button
                onClick={handleStatusUpdate}
                className="w-full h-14 text-base font-bold gradient-wallet text-primary-foreground ring-glow-primary hover:opacity-95"
              >
                <CheckCircle className="w-5 h-5 mr-2" />
                {statusInfo[activeOrder.status].action}
              </Button>
            </div>
          </motion.div>
        </div>
      ) : (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="px-4 py-12 text-center"
        >
          <div className="w-20 h-20 rounded-full bg-muted mx-auto flex items-center justify-center mb-4">
            <Clock className="w-10 h-10 text-muted-foreground" />
          </div>
          <h3 className="text-lg font-semibold text-foreground mb-2">
            Aucune course active
          </h3>
          <p className="text-muted-foreground text-sm">
            Acceptez une nouvelle demande pour commencer
          </p>
        </motion.div>
      )}

      {/* Bottom-sheet popup lives in the Courses tab only */}
      <IncomingRequestPopup
        request={current}
        onAccept={accept}
        onDecline={decline}
        timeoutSec={20}
      />
    </div>
  );
}
