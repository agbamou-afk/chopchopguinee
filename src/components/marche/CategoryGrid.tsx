import { motion } from "framer-motion";
import { MARCHE_CATEGORIES } from "@/lib/marche";

export function CategoryGrid({
  active,
  onSelect,
}: {
  active?: string | null;
  onSelect: (id: string) => void;
}) {
  return (
    <div className="grid grid-cols-4 gap-3">
      {MARCHE_CATEGORIES.map((c) => {
        const Icon = c.icon;
        const isActive = active === c.id;
        return (
          <motion.button
            key={c.id}
            whileTap={{ scale: 0.94 }}
            onClick={() => onSelect(c.id)}
            className={`flex flex-col items-center gap-1.5 rounded-2xl p-2 transition ${
              isActive ? "ring-2 ring-primary" : ""
            }`}
          >
            <div className={`w-12 h-12 rounded-2xl ${c.tint} flex items-center justify-center shadow-card`}>
              <Icon className={`w-5 h-5 ${c.fg}`} />
            </div>
            <span className="text-[10px] font-medium text-foreground text-center leading-tight">
              {c.label}
            </span>
          </motion.button>
        );
      })}
    </div>
  );
}