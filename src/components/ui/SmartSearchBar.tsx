import { Search } from "lucide-react";
import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";

interface SmartSearchBarProps {
  prompts?: string[];
  onClick?: () => void;
  intervalMs?: number;
}

const DEFAULT_PROMPTS = [
  "Où allez-vous ?",
  "Commandez un repas",
  "Rechercher dans Marché",
  "Envoyer un colis",
  "Trouver un chauffeur",
];

export function SmartSearchBar({ prompts = DEFAULT_PROMPTS, onClick, intervalMs = 2400 }: SmartSearchBarProps) {
  const [idx, setIdx] = useState(0);

  useEffect(() => {
    const id = setInterval(() => setIdx((i) => (i + 1) % prompts.length), intervalMs);
    return () => clearInterval(id);
  }, [prompts.length, intervalMs]);

  return (
    <button
      onClick={onClick}
      className="w-full h-14 flex items-center gap-3 px-4 bg-card rounded-2xl shadow-soft border border-border/60 text-left hover:border-primary/40 transition-colors group"
    >
      <div className="w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center shrink-0 group-hover:bg-primary/15 transition-colors">
        <Search className="w-4 h-4 text-primary" />
      </div>
      <div className="relative flex-1 h-5 overflow-hidden">
        <AnimatePresence mode="wait">
          <motion.span
            key={prompts[idx]}
            initial={{ y: 14, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: -14, opacity: 0 }}
            transition={{ duration: 0.35, ease: "easeOut" }}
            className="absolute inset-0 flex items-center text-sm text-muted-foreground"
          >
            {prompts[idx]}
          </motion.span>
        </AnimatePresence>
      </div>
      <span className="hidden xs:inline text-[10px] uppercase tracking-wider text-muted-foreground/70">⌘K</span>
    </button>
  );
}