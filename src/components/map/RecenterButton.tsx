import { LocateFixed } from "lucide-react";
import { cn } from "@/lib/utils";

interface Props {
  onClick: () => void;
  /** Visual style. `floating` is a circular FAB; `inline` is a chip with label. */
  variant?: "floating" | "inline";
  /** Disable interactions (e.g., GPS not ready). */
  disabled?: boolean;
  label?: string;
  className?: string;
}

/**
 * Universal map recenter control. Used across driver active trip, customer
 * tracking, admin live ops, and booking screens so the affordance is
 * consistent everywhere a CHOPCHOP map appears.
 */
export function RecenterButton({ onClick, variant = "floating", disabled, label = "Recentrer", className }: Props) {
  if (variant === "inline") {
    return (
      <button
        type="button" onClick={onClick} disabled={disabled} aria-label={label}
        className={cn(
          "inline-flex items-center gap-1.5 h-9 px-3 rounded-full border border-border/60 bg-card/95 backdrop-blur text-xs font-semibold text-foreground shadow-card active:scale-[0.97] transition disabled:opacity-50",
          className,
        )}
      >
        <LocateFixed className="w-3.5 h-3.5 text-primary" />
        {label}
      </button>
    );
  }
  return (
    <button
      type="button" onClick={onClick} disabled={disabled} aria-label={label}
      className={cn(
        "w-11 h-11 rounded-full bg-card/95 backdrop-blur border border-border/60 shadow-elevated flex items-center justify-center text-primary active:scale-95 transition disabled:opacity-50",
        className,
      )}
    >
      <LocateFixed className="w-5 h-5" />
    </button>
  );
}
