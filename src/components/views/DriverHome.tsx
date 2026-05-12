import { motion, AnimatePresence } from "framer-motion";
import { Power } from "lucide-react";
import { useState } from "react";
import { DriverDashboard } from "@/components/driver/DriverDashboard";
import { OrderRequest } from "@/components/driver/OrderRequest";
import { AppHeader } from "@/components/ui/AppHeader";
import { toast } from "sonner";

interface DriverHomeProps {
  onToggleDriverMode: () => void;
}

const mockOrders = [
  {
    id: "1",
    type: "ride" as const,
    pickup: "Marché Madina, Conakry",
    destination: "Aéroport International",
    customerName: "Amadou Diallo",
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
    estimatedPrice: 25000,
    distance: "5 km",
    eta: "15 min",
  },
];

export function DriverHome({ onToggleDriverMode }: DriverHomeProps) {
  const [isOnline, setIsOnline] = useState(true);
  const [orders, setOrders] = useState(mockOrders);

  const handleAcceptOrder = (id: string) => {
    setOrders(orders.filter((o) => o.id !== id));
    toast.success("Course acceptée ! En route vers le client.");
  };

  const handleDeclineOrder = (id: string) => {
    setOrders(orders.filter((o) => o.id !== id));
    toast.info("Course refusée");
  };

  return (
    <div className="max-w-md mx-auto">
      <AppHeader
        isDriverMode={true}
        onToggleDriverMode={onToggleDriverMode}
        subtitle="Tableau de bord chauffeur"
        amountLabel="Gains du jour"
        amountValue={185000}
        notificationCount={orders.length}
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

        {/* Pending orders */}
        {isOnline && orders.length > 0 && (
          <section>
            <h2 className="text-lg font-semibold text-foreground mb-4">
              Nouvelles demandes ({orders.length})
            </h2>
            <div className="space-y-3">
              <AnimatePresence>
                {orders.map((order) => (
                  <OrderRequest
                    key={order.id}
                    order={order}
                    onAccept={handleAcceptOrder}
                    onDecline={handleDeclineOrder}
                  />
                ))}
              </AnimatePresence>
            </div>
          </section>
        )}

        {isOnline && orders.length === 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-center py-12"
          >
            <div className="w-20 h-20 rounded-full bg-muted mx-auto flex items-center justify-center mb-4">
              <Power className="w-10 h-10 text-muted-foreground" />
            </div>
            <h3 className="text-lg font-semibold text-foreground mb-2">
              En attente de courses
            </h3>
            <p className="text-muted-foreground text-sm">
              Les nouvelles demandes apparaîtront ici
            </p>
          </motion.div>
        )}
      </div>
    </div>
  );
}
