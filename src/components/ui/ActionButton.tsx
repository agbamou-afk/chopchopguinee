import { LucideIcon } from "lucide-react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

/**
 * ActionButton — square icon+label tile used in services / quick actions / wallet actions.
 * Visual weight is uniform regardless of tone.
 */
interface ActionButtonProps {
  icon: LucideIcon;
  label: string;
  onClick?: () => void;
  tone?: "primary" | "secondary" | "destructive" | "neutral";
  className?: string;
}

const toneChip: Record<NonNullable<ActionButtonProps["tone"]>, string> = {
  primary: "bg-brand-green-muted text-primary",
  secondary: "bg-brand-yellow-muted text-secondary-foreground",
  destructive: "bg-brand-red-muted text-destructive",
  neutral: "bg-muted text-foreground",
};

export function ActionButton({
  icon: Icon,
  label,
  onClick,
  tone = "primary",
  className,
}: ActionButtonProps) {
  return (
    <motion.button
      whileTap={{ scale: 0.96 }}
      onClick={onClick}
      className={cn(
        "flex flex-col items-center gap-2 p-3 rounded-xl bg-card shadow-card",
        "active:shadow-soft transition",
        className,
      )}
    >
      <span
        className={cn(
          "w-12 h-12 rounded-xl flex items-center justify-center",
          toneChip[tone],
        )}
      >
        <Icon className="w-6 h-6" />
      </span>
      <span className="text-xs font-medium text-foreground text-center leading-tight">
        {label}
      </span>
    </motion.button>
  );
}