import { motion } from "framer-motion";
import { ChevronRight } from "lucide-react";

const promos = [
  {
    id: 1,
    title: "50% de réduction",
    subtitle: "Sur votre première course Moto",
    gradient: "gradient-primary",
  },
  {
    id: 2,
    title: "Livraison gratuite",
    subtitle: "Pour les commandes +200,000 GNF",
    gradient: "gradient-secondary",
  },
  {
    id: 3,
    title: "Parrainez un ami",
    subtitle: "Gagnez 50,000 GNF chacun",
    gradient: "bg-destructive",
  },
];

export function PromoCarousel() {
  return (
    <div className="overflow-x-auto scrollbar-hide -mx-4 px-4">
      <div className="flex gap-3" style={{ width: "max-content" }}>
        {promos.map((promo, index) => (
          <motion.div
            key={promo.id}
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: index * 0.1 }}
            className={`${promo.gradient} rounded-2xl p-4 min-w-[260px] text-primary-foreground`}
          >
            <h3 className="text-lg font-bold">{promo.title}</h3>
            <p className="text-sm opacity-90 mt-1">{promo.subtitle}</p>
            <button className="flex items-center gap-1 mt-3 text-sm font-medium bg-white/20 hover:bg-white/30 px-3 py-1.5 rounded-full transition-colors">
              En profiter
              <ChevronRight className="w-4 h-4" />
            </button>
          </motion.div>
        ))}
      </div>
    </div>
  );
}
