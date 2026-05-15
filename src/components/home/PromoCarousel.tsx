import { motion } from "framer-motion";
import { ChevronRight } from "lucide-react";
import { useEffect, useRef } from "react";

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
    subtitle: "Pour les commandes +200\u00A0000\u00A0GNF",
    gradient: "gradient-secondary",
  },
  {
    id: 3,
    title: "Parrainez un ami",
    subtitle: "Gagnez 50\u00A0000\u00A0GNF chacun",
    gradient: "gradient-wallet-premium",
  },
];

export function PromoCarousel() {
  const scrollerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scrollerRef.current;
    if (!el) return;
    let paused = false;
    const onEnter = () => (paused = true);
    const onLeave = () => (paused = false);
    el.addEventListener("pointerdown", onEnter);
    el.addEventListener("pointerup", onLeave);
    el.addEventListener("pointerleave", onLeave);
    const id = setInterval(() => {
      if (paused || !el) return;
      const max = el.scrollWidth - el.clientWidth;
      if (max <= 0) return;
      const next = el.scrollLeft + 280;
      el.scrollTo({ left: next >= max - 4 ? 0 : next, behavior: "smooth" });
    }, 4200);
    return () => {
      clearInterval(id);
      el.removeEventListener("pointerdown", onEnter);
      el.removeEventListener("pointerup", onLeave);
      el.removeEventListener("pointerleave", onLeave);
    };
  }, []);

  return (
    <div ref={scrollerRef} className="overflow-x-auto scrollbar-hide -mx-4 px-4 scroll-smooth">
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
