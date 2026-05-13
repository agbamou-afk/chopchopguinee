import { motion } from "framer-motion";
import type { LucideIcon } from "lucide-react";

export interface LiveStat {
  icon: LucideIcon;
  label: string;
  tone?: string;
  bg?: string;
}

interface LiveStripProps {
  stats: LiveStat[];
  className?: string;
}

export function LiveStrip({ stats, className = "" }: LiveStripProps) {
  return (
    <div className={`flex gap-2 overflow-x-auto scrollbar-hide -mx-4 px-4 ${className}`}>
      {stats.map((s) => (
        <motion.div
          key={s.label}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className={`shrink-0 inline-flex items-center gap-2 ${s.bg ?? "bg-primary/10"} rounded-full pl-2 pr-3 py-1.5`}
        >
          <span className="relative flex h-1.5 w-1.5">
            <span className="absolute inline-flex h-full w-full rounded-full bg-success opacity-70 pulse-dot" />
            <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-success" />
          </span>
          <s.icon className={`w-3.5 h-3.5 ${s.tone ?? "text-primary"}`} />
          <span className="text-[11px] font-semibold text-foreground whitespace-nowrap">{s.label}</span>
        </motion.div>
      ))}
    </div>
  );
}