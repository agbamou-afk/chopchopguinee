import { motion, AnimatePresence } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { MapPin, Navigation, Clock, User, X, Check } from "lucide-react";
import { Button } from "@/components/ui/button";

interface OrderRequestProps {
  order: {
    id: string;
    type: "ride" | "delivery" | "food";
    pickup: string;
    destination: string;
    customerName: string;
    estimatedPrice: number;
    distance: string;
    eta: string;
  };
  onAccept: (id: string) => void;
  onDecline: (id: string) => void;
}

export function OrderRequest({ order, onAccept, onDecline }: OrderRequestProps) {
  const formatMoney = (amount: number) =>
    formatGNF(amount);

  const typeLabels = {
    ride: "Course",
    delivery: "Livraison",
    food: "Repas",
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 50, scale: 0.9 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: 50, scale: 0.9 }}
      className="bg-card rounded-2xl p-5 shadow-elevated border border-border"
    >
      <div className="flex items-center justify-between mb-4">
        <span className="px-3 py-1 rounded-full bg-primary/10 text-primary text-sm font-medium">
          {typeLabels[order.type]}
        </span>
        <div className="flex items-center gap-2">
          <Clock className="w-4 h-4 text-muted-foreground" />
          <span className="text-sm text-muted-foreground">{order.eta}</span>
        </div>
      </div>

      <div className="space-y-3 mb-4">
        <div className="flex items-start gap-3">
          <div className="mt-1">
            <div className="w-3 h-3 rounded-full bg-primary" />
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Départ</p>
            <p className="text-sm font-medium text-foreground">{order.pickup}</p>
          </div>
        </div>
        <div className="flex items-start gap-3">
          <div className="mt-1">
            <div className="w-3 h-3 rounded-full bg-secondary" />
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Destination</p>
            <p className="text-sm font-medium text-foreground">{order.destination}</p>
          </div>
        </div>
      </div>

      <div className="flex items-center justify-between py-3 border-t border-border">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-full bg-muted flex items-center justify-center">
            <User className="w-4 h-4 text-muted-foreground" />
          </div>
          <span className="text-sm text-foreground">{order.customerName}</span>
        </div>
        <div className="text-right">
          <p className="text-lg font-bold text-foreground">
            {formatMoney(order.estimatedPrice)} GNF
          </p>
          <p className="text-xs text-muted-foreground">{order.distance}</p>
        </div>
      </div>

      <div className="flex gap-3 mt-4">
        <Button
          variant="outline"
          onClick={() => onDecline(order.id)}
          className="flex-1 h-12 border-destructive text-destructive hover:bg-destructive hover:text-destructive-foreground"
        >
          <X className="w-5 h-5 mr-2" />
          Refuser
        </Button>
        <Button
          onClick={() => onAccept(order.id)}
          className="flex-1 h-12 gradient-primary hover:opacity-90"
        >
          <Check className="w-5 h-5 mr-2" />
          Accepter
        </Button>
      </div>
    </motion.div>
  );
}
