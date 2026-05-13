import { motion } from "framer-motion";
import { ArrowLeft } from "lucide-react";
import type { ReactNode } from "react";

interface ScreenHeaderProps {
  title: string;
  subtitle?: string;
  onBack?: () => void;
  right?: ReactNode;
  sticky?: boolean;
  variant?: "plain" | "card";
}

/**
 * ScreenHeader — unified premium page header.
 * - Bold title, soft subtitle
 * - Optional back button + right slot (filters, calendar, etc.)
 * - Subtle brand wash for visual depth
 */
export function ScreenHeader({
  title,
  subtitle,
  onBack,
  right,
  sticky = false,
  variant = "plain",
}: ScreenHeaderProps) {
  const base =
    variant === "card"
      ? "relative overflow-hidden bg-card rounded-[28px] shadow-soft border border-border/60 px-5 pt-4 pb-5 mx-4 mt-4"
      : `relative ${sticky ? "sticky top-0 z-30" : ""} bg-background/85 backdrop-blur-md px-4 pt-5 pb-4`;

  return (
    <motion.header
      initial={{ opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      className={base}
    >
      {variant === "card" && (
        <>
          <div className="pointer-events-none absolute -top-20 -right-16 w-56 h-56 rounded-full bg-primary/10 blur-3xl" aria-hidden />
          <div className="pointer-events-none absolute -bottom-24 -left-12 w-48 h-48 rounded-full bg-secondary/10 blur-3xl" aria-hidden />
        </>
      )}
      <div className="relative flex items-center gap-3">
        {onBack && (
          <button
            onClick={onBack}
            aria-label="Retour"
            className="w-10 h-10 rounded-full bg-card border border-border/60 hover:bg-muted transition-colors flex items-center justify-center shrink-0"
          >
            <ArrowLeft className="w-5 h-5 text-foreground" />
          </button>
        )}
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-extrabold text-foreground leading-tight truncate">{title}</h1>
          {subtitle && (
            <p className="text-xs text-muted-foreground mt-0.5 truncate">{subtitle}</p>
          )}
        </div>
        {right && <div className="shrink-0">{right}</div>}
      </div>
    </motion.header>
  );
}