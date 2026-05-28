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
    <div className="grid grid-cols-4 gap-2.5">
      {MARCHE_CATEGORIES.map((c) => {
        const isActive = active === c.id;
        return (
          <motion.button
            key={c.id}
            whileTap={{ scale: 0.94 }}
            onClick={() => onSelect(c.id)}
            className={`flex flex-col items-center gap-2 rounded-2xl p-2 transition ${
              isActive ? "ring-2 ring-primary" : ""
            }`}
          >
            <div
              className={`w-[3.75rem] h-[3.75rem] rounded-2xl ${c.tint} flex items-center justify-center shadow-card overflow-hidden`}
            >
              <img
                src={c.icon}
                alt=""
                className="w-10 h-10 object-contain block"
                style={{ objectPosition: "center" }}
                loading="lazy"
              />
            </div>
            <span className="text-[11px] font-semibold text-foreground text-center leading-tight">
              {c.label}
            </span>
          </motion.button>
        );
      })}
    </div>
  );
}