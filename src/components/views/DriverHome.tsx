import { motion, AnimatePresence } from "framer-motion";
import { Power, BellRing } from "lucide-react";
import { useEffect, useState } from "react";
import { DriverDashboard } from "@/components/driver/DriverDashboard";
import { IncomingRequestPopup, type IncomingRequest } from "@/components/driver/IncomingRequestPopup";
import { DriverTripView } from "@/components/driver/DriverTripView";
import { AppHeader } from "@/components/ui/AppHeader";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { LiveRidesPanel } from "@/components/driver/LiveRidesPanel";

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
      />

      {/* Content */}
      <div className="px-4 mt-6 space-y-4">
        {/* Online toggle */}
        <motion.button
          whileTap={{ scale: 0.95 }}
          onClick={() => setIsOnline(!isOnline)}
          className={`w-full flex items-center justify-center gap-3 py-4 rounded-2xl shadow-card ${
            isOnline
              ? "bg-secondary text-secondary-foreground"
              : "bg-muted text-foreground"
          } transition-colors`}
        >
          <Power className="w-5 h-5" />
          <span className="font-semibold">
            {isOnline ? "En ligne - Recherche de courses" : "Hors ligne - Appuyez pour commencer"}
          </span>
        </motion.button>

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
