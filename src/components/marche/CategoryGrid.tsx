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
              className="w-[3.75rem] h-[3.75rem] rounded-full flex items-center justify-center"
              style={{
                background:
                  "radial-gradient(circle at 50% 50%, hsl(0 0% 100%) 0%, hsl(0 0% 100%) 56%, hsl(40 18% 92%) 78%, hsl(40 16% 86%) 100%)",
                boxShadow:
                  "inset 0 0 0 0.5px hsl(40 14% 84% / 0.6), 0 1px 2px hsl(30 20% 30% / 0.06)",
              }}
            >
              <img
                src={c.icon}
                alt=""
                className="w-9 h-9 object-contain block m-auto"
                style={{ objectPosition: "center", mixBlendMode: "multiply" }}
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