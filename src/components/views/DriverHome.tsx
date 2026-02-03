import { motion } from "framer-motion";
import { Bell, Power, ToggleLeft } from "lucide-react";
import { useState } from "react";
import { DriverDashboard } from "@/components/driver/DriverDashboard";
import { OrderRequest } from "@/components/driver/OrderRequest";
import { AnimatePresence } from "framer-motion";
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
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className={`${isOnline ? "gradient-hero" : "bg-muted"} text-${isOnline ? "primary-foreground" : "foreground"} px-4 pt-6 pb-8 rounded-b-3xl transition-colors`}
      >
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className={`text-sm ${isOnline ? "opacity-80" : "text-muted-foreground"}`}>Mode Chauffeur</p>
            <h1 className="text-xl font-bold">Tableau de bord</h1>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={onToggleDriverMode}
              className={`p-2 rounded-full ${isOnline ? "bg-white/20 hover:bg-white/30" : "bg-muted-foreground/20 hover:bg-muted-foreground/30"} transition-colors`}
              title="Mode client"
            >
              <ToggleLeft className="w-5 h-5" />
            </button>
            <button className={`p-2 rounded-full ${isOnline ? "bg-white/20 hover:bg-white/30" : "bg-muted-foreground/20 hover:bg-muted-foreground/30"} transition-colors relative`}>
              <Bell className="w-5 h-5" />
              {orders.length > 0 && (
                <span className="absolute -top-1 -right-1 w-5 h-5 bg-destructive rounded-full flex items-center justify-center text-xs font-bold text-destructive-foreground">
                  {orders.length}
                </span>
              )}
            </button>
          </div>
        </div>

        {/* Online toggle */}
        <motion.button
          whileTap={{ scale: 0.95 }}
          onClick={() => setIsOnline(!isOnline)}
          className={`w-full flex items-center justify-center gap-3 py-4 rounded-xl ${
            isOnline 
              ? "bg-white/20 hover:bg-white/30" 
              : "bg-primary text-primary-foreground"
          } transition-colors`}
        >
          <Power className="w-5 h-5" />
          <span className="font-semibold">
            {isOnline ? "En ligne - Recherche de courses" : "Hors ligne - Appuyez pour commencer"}
          </span>
        </motion.button>
      </motion.header>

      {/* Content */}
      <div className="px-4 -mt-4 space-y-4">
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
