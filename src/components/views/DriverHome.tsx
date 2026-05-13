import { motion } from "framer-motion";
import { Power, BellRing, Radar, Users, Star, TrendingUp, Timer } from "lucide-react";
import { useEffect, useState } from "react";
import { DriverDashboard } from "@/components/driver/DriverDashboard";
import { IncomingRequestPopup, type IncomingRequest } from "@/components/driver/IncomingRequestPopup";
import { DriverTripView } from "@/components/driver/DriverTripView";
import { AppHeader } from "@/components/ui/AppHeader";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { LiveRidesPanel } from "@/components/driver/LiveRidesPanel";
import { LiveStrip } from "@/components/ui/LiveStrip";

interface DriverHomeProps {
  onToggleDriverMode: () => void;
}

const mockOrders: IncomingRequest[] = [
  {
    id: "1",
    type: "ride" as const,
    pickup: "Marché Madina, Conakry",
    destination: "Aéroport International",
    customerName: "Amadou Diallo",
    customerRating: 4.7,
    estimatedPrice: 45000,
    distance: "12 km",
    eta: "25 min",
  },
  {
    id: "2",
    type: "food" as const,
    pickup: "Restaurant Chez Mama",
    destination: "Kipé Dadia",
    customerName: "Mariama Bah",
    customerRating: 4.9,
    estimatedPrice: 25000,
    distance: "5 km",
    eta: "15 min",
  },
  {
    id: "3",
    type: "delivery" as const,
    pickup: "Carrefour Hamdallaye",
    destination: "Rond-point Bambeto",
    customerName: "Ousmane Bah",
    customerRating: 4.6,
    estimatedPrice: 18000,
    distance: "4 km",
    eta: "12 min",
  },
];

export function DriverHome({ onToggleDriverMode }: DriverHomeProps) {
  const [isOnline, setIsOnline] = useState(true);
  const [queue, setQueue] = useState<IncomingRequest[]>(mockOrders);
  const [current, setCurrent] = useState<IncomingRequest | null>(null);
  const [activeTrip, setActiveTrip] = useState<IncomingRequest | null>(null);

  // Auto-pop next request when online and idle
  useEffect(() => {
    if (!isOnline || current || activeTrip || queue.length === 0) return;
    const t = setTimeout(() => {
      setCurrent(queue[0]);
      setQueue((q) => q.slice(1));
    }, 2500);
    return () => clearTimeout(t);
  }, [isOnline, current, activeTrip, queue]);

  const handleAccept = (id: string) => {
    const accepted = current;
    setCurrent(null);
    if (accepted) {
      setActiveTrip(accepted);
      toast.success("Course acceptée ! Navigation lancée vers le client.");
    }
  };

  const handleDecline = (id: string) => {
    setCurrent(null);
    toast.info("Course refusée");
  };

  const triggerNext = () => {
    if (queue.length === 0) {
      toast.info("Aucune demande en attente");
      return;
    }
    setCurrent(queue[0]);
    setQueue((q) => q.slice(1));
  };

  return (
    <div className="max-w-md mx-auto">
      <AppHeader
        isDriverMode={true}
        onToggleDriverMode={onToggleDriverMode}
        subtitle="Tableau de bord chauffeur"
        amountLabel="Gains du jour"
        amountValue={185000}
        notificationCount={queue.length + (current ? 1 : 0)}
        location="Conakry, en service"
      />

      {/* Content */}
      <div className="px-4 mt-5 space-y-4">
        <LiveStrip
          stats={[
            { icon: Users, label: `${queue.length} demandes proches`, bg: "bg-primary/10", tone: "text-primary" },
            { icon: Timer, label: "Temps moyen 12 min", bg: "bg-secondary/20", tone: "text-foreground" },
            { icon: Star, label: "Note 4.9", bg: "bg-[hsl(45_90%_55%/0.14)]", tone: "text-[hsl(38_85%_40%)]" },
            { icon: TrendingUp, label: "+18% cette semaine", bg: "bg-success/10", tone: "text-success" },
          ]}
        />
        {/* Online toggle — 3 states: Hors ligne / En ligne / Recherche */}
        {(() => {
          const searching = isOnline && !current && !activeTrip;
          const label = !isOnline
            ? "Hors ligne — appuyez pour commencer"
            : searching
              ? "Recherche de courses…"
              : "En ligne — course en cours";
          const tone = !isOnline
            ? "bg-card border border-border text-foreground shadow-card"
            : searching
              ? "gradient-wallet text-primary-foreground ring-glow-primary"
              : "bg-secondary text-secondary-foreground shadow-card";
          return (
            <motion.button
              whileTap={{ scale: 0.97 }}
              onClick={() => setIsOnline(!isOnline)}
              className={`w-full relative flex items-center justify-center gap-3 py-4 rounded-2xl overflow-hidden ${tone} transition-colors`}
            >
              {searching && (
                <motion.span
                  aria-hidden
                  className="absolute inset-0 bg-white/10"
                  animate={{ opacity: [0.05, 0.25, 0.05] }}
                  transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
                />
              )}
              {isOnline ? <Radar className="w-5 h-5 relative" /> : <Power className="w-5 h-5 relative" />}
              <span className="font-bold relative">{label}</span>
            </motion.button>
          );
        })()}

        <DriverDashboard
          todayEarnings={185000}
          weeklyEarnings={1250000}
          completedRides={12}
          onlineHours={6}
        />

        <LiveRidesPanel />

        {isOnline && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-center py-8"
          >
            <div className="w-20 h-20 rounded-full bg-muted mx-auto flex items-center justify-center mb-4">
              <BellRing className="w-10 h-10 text-muted-foreground" />
            </div>
            <h3 className="text-lg font-semibold text-foreground mb-2">
              {queue.length > 0 ? `${queue.length} demande(s) en file` : "En attente de courses"}
            </h3>
            <p className="text-muted-foreground text-sm mb-4">
              Les nouvelles demandes apparaîtront ici
            </p>
            {queue.length > 0 && (
              <Button onClick={triggerNext} variant="outline" className="h-11">
                <BellRing className="w-4 h-4 mr-2" /> Voir la demande suivante
              </Button>
            )}
          </motion.div>
        )}
      </div>

      <IncomingRequestPopup
        request={current}
        onAccept={handleAccept}
        onDecline={handleDecline}
        timeoutSec={20}
      />

      {activeTrip && (
        <DriverTripView request={activeTrip} onClose={() => setActiveTrip(null)} />
      )}
    </div>
  );
}
