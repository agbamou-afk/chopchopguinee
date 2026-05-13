import { Search, Sparkles } from "lucide-react";
import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { CommandBarSheet } from "@/components/ai/CommandBarSheet";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface SmartSearchBarProps {
  prompts?: string[];
  /** Called when the assistant routes the user to an action. */
  onAction?: (action: string, params?: { destination?: string }) => void;
  /** Optional click override; if provided, replaces the default AI assistant. */
  onClick?: () => void;
  intervalMs?: number;
  location?: string;
}

const DEFAULT_PROMPTS = [
  "Où allez-vous ?",
  "Rechercher dans Marché",
  "Commander un repas",
  "Envoyer un colis",
  "Recharger mon portefeuille",
];

export function SmartSearchBar({
  prompts = DEFAULT_PROMPTS,
  onAction,
  onClick,
  intervalMs = 2400,
  location,
}: SmartSearchBarProps) {
  const [idx, setIdx] = useState(0);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const id = setInterval(() => setIdx((i) => (i + 1) % prompts.length), intervalMs);
    return () => clearInterval(id);
  }, [prompts.length, intervalMs]);

  return (
    <>
      <button
        onClick={onClick ?? (() => { Analytics.track("commandbar.opened", { metadata: { source: "home" } }); setOpen(true); })}
        className="w-full h-14 flex items-center gap-3 px-4 bg-card rounded-2xl shadow-soft border border-border/60 text-left hover:border-primary/40 transition-colors group"
        aria-label="Ouvrir l'assistant CHOP CHOP"
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
        <span className="inline-flex items-center gap-1 text-[10px] font-semibold uppercase tracking-wider text-primary bg-primary/10 px-2 py-1 rounded-full">
          <Sparkles className="w-3 h-3" /> IA
        </span>
      </button>
      {!onClick && (
        <CommandBarSheet
          open={open}
          onOpenChange={setOpen}
          onAction={(a, params) => onAction?.(a, params)}
          location={location}
        />
      )}
    </>
  );
}