import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { Clock, Navigation, Phone, MessageCircle, CheckCircle, Users, Timer } from "lucide-react";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { Button } from "@/components/ui/button";
import { useState } from "react";
import { toast } from "sonner";

interface ActiveOrder {
  id: string;
  customerName: string;
  customerPhone: string;
  pickup: string;
  destination: string;
  estimatedPrice: number;
  status: "pickup" | "in_transit" | "arrived";
}

export function DriverOrdersView() {
  const [activeOrder, setActiveOrder] = useState<ActiveOrder | null>({
    id: "CHO-2024-001",
    customerName: "Amadou Diallo",
    customerPhone: "+224 622 123 456",
    pickup: "Marché Madina, Conakry",
    destination: "Aéroport International Ahmed Sékou Touré",
    estimatedPrice: 45000,
    status: "pickup",
  });

  const formatMoney = (amount: number) =>
    formatGNF(amount);

  const handleStatusUpdate = () => {
    if (!activeOrder) return;

    if (activeOrder.status === "pickup") {
      setActiveOrder({ ...activeOrder, status: "in_transit" });
      toast.success("Client récupéré ! En route vers la destination.");
    } else if (activeOrder.status === "in_transit") {
      setActiveOrder({ ...activeOrder, status: "arrived" });
      toast.success("Arrivé à destination !");
    } else {
      setActiveOrder(null);
      toast.success("Course terminée ! Gains ajoutés.");
    }
  };

  const statusInfo = {
    pickup: {
      label: "En route pour récupérer",
      action: "Client récupéré",
      color: "bg-primary",
    },
    in_transit: {
      label: "En route vers destination",
      action: "Arrivé à destination",
      color: "bg-secondary",
    },
    arrived: {
      label: "À destination",
      action: "Terminer la course",
      color: "bg-success",
    },
  };

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader title="Mes courses" subtitle="Gérez vos courses en cours" />

      <div className="mt-4 mb-2">
        <LiveStrip
          stats={[
            { icon: Users, label: "Demandes proches", bg: "bg-primary/10", tone: "text-primary" },
            { icon: Timer, label: "Navigation en direct", bg: "bg-secondary/20", tone: "text-foreground" },
          ]}
        />
      </div>

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
    </div>
  );
}
