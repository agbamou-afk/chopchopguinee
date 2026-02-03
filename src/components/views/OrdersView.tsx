import { motion } from "framer-motion";
import { Package, MapPin, Clock, ChevronRight, Bike, UtensilsCrossed, ShoppingBag } from "lucide-react";

const orders = [
  {
    id: "CHO-2024-001",
    type: "ride" as const,
    status: "in_progress",
    title: "Course en cours",
    from: "Marché Madina",
    to: "Kipé Dadia",
    time: "En cours",
    driver: "Ibrahim B.",
    price: 15000,
  },
  {
    id: "CHO-2024-002",
    type: "food" as const,
    status: "preparing",
    title: "Commande en préparation",
    from: "Chez Mama Fatoumata",
    to: "Kipé Dadia",
    time: "~20 min",
    price: 35000,
  },
  {
    id: "CHO-2024-003",
    type: "delivery" as const,
    status: "completed",
    title: "Livraison terminée",
    from: "Marché Choper",
    to: "Ratoma Centre",
    time: "Hier, 16:30",
    price: 180000,
  },
];

const statusColors = {
  in_progress: "bg-primary",
  preparing: "bg-secondary",
  completed: "bg-muted",
};

const statusLabels = {
  in_progress: "En cours",
  preparing: "En préparation",
  completed: "Terminée",
};

const typeIcons = {
  ride: Bike,
  food: UtensilsCrossed,
  delivery: ShoppingBag,
};

export function OrdersView() {
  const formatMoney = (amount: number) =>
    new Intl.NumberFormat("fr-GN").format(amount);

  return (
    <div className="max-w-md mx-auto">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="px-4 pt-6 pb-4"
      >
        <h1 className="text-2xl font-bold text-foreground">Mes commandes</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Suivez vos courses et livraisons
        </p>
      </motion.header>

      {/* Tabs */}
      <div className="px-4 mb-4">
        <div className="flex gap-2 bg-muted rounded-xl p-1">
          <button className="flex-1 py-2 rounded-lg gradient-primary text-primary-foreground text-sm font-medium">
            En cours
          </button>
          <button className="flex-1 py-2 rounded-lg text-muted-foreground text-sm font-medium hover:text-foreground transition-colors">
            Historique
          </button>
        </div>
      </div>

      {/* Orders list */}
      <div className="px-4 pb-6 space-y-3">
        {orders.map((order, index) => {
          const Icon = typeIcons[order.type];
          return (
            <motion.div
              key={order.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.1 }}
              className="bg-card rounded-2xl p-4 shadow-card"
            >
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <div className="p-2 rounded-xl bg-primary/10">
                    <Icon className="w-4 h-4 text-primary" />
                  </div>
                  <div>
                    <p className="font-medium text-foreground text-sm">
                      {order.title}
                    </p>
                    <p className="text-xs text-muted-foreground">{order.id}</p>
                  </div>
                </div>
                <span
                  className={`px-2 py-1 rounded-full text-xs font-medium ${
                    order.status === "completed"
                      ? "bg-muted text-muted-foreground"
                      : order.status === "in_progress"
                      ? "bg-primary/10 text-primary"
                      : "bg-secondary/10 text-secondary-foreground"
                  }`}
                >
                  {statusLabels[order.status]}
                </span>
              </div>

              <div className="space-y-2 mb-3">
                <div className="flex items-center gap-2 text-sm">
                  <div className="w-2 h-2 rounded-full bg-primary" />
                  <span className="text-muted-foreground">De:</span>
                  <span className="text-foreground">{order.from}</span>
                </div>
                <div className="flex items-center gap-2 text-sm">
                  <div className="w-2 h-2 rounded-full bg-secondary" />
                  <span className="text-muted-foreground">À:</span>
                  <span className="text-foreground">{order.to}</span>
                </div>
              </div>

              <div className="flex items-center justify-between pt-3 border-t border-border">
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Clock className="w-4 h-4" />
                  <span>{order.time}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-foreground">
                    {formatMoney(order.price)} GNF
                  </span>
                  <ChevronRight className="w-4 h-4 text-muted-foreground" />
                </div>
              </div>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}
