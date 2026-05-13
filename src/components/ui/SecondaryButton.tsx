import { ButtonHTMLAttributes, forwardRef } from "react";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

interface SecondaryButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  loading?: boolean;
  fullWidth?: boolean;
  size?: "md" | "lg";
  tone?: "neutral" | "danger";
}

export const SecondaryButton = forwardRef<HTMLButtonElement, SecondaryButtonProps>(
  (
    { className, loading, fullWidth = true, size = "lg", tone = "neutral", disabled, children, ...props },
    ref,
  ) => {
    return (
      <button
        ref={ref}
        disabled={disabled || loading}
        className={cn(
          "inline-flex items-center justify-center gap-2 rounded-xl font-semibold border",
          tone === "danger"
            ? "bg-background text-destructive border-destructive/30 hover:bg-destructive/5"
            : "bg-card text-foreground border-border hover:bg-muted",
          "active:scale-[0.98] transition disabled:opacity-60 disabled:active:scale-100",
          size === "lg" ? "h-12 px-6 text-base" : "h-10 px-4 text-sm",
          fullWidth && "w-full",
          className,
        )}
        {...props}
      >
        {loading && <Loader2 className="w-4 h-4 animate-spin" />}
        {children}
      </button>
    );
  },
);
SecondaryButton.displayName = "SecondaryButton";