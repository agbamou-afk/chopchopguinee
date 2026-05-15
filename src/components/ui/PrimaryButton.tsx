import { ButtonHTMLAttributes, forwardRef } from "react";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

interface PrimaryButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  loading?: boolean;
  fullWidth?: boolean;
  size?: "md" | "lg";
}

export const PrimaryButton = forwardRef<HTMLButtonElement, PrimaryButtonProps>(
  ({ className, loading, fullWidth = true, size = "lg", disabled, children, ...props }, ref) => {
    return (
      <button
        ref={ref}
        disabled={disabled || loading}
        className={cn(
          "inline-flex items-center justify-center gap-2 rounded-xl font-semibold",
          "gradient-cta text-primary-foreground",
          "active:scale-[0.985] transition-[transform,box-shadow] duration-200 ease-out",
          "disabled:opacity-60 disabled:active:scale-100",
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
PrimaryButton.displayName = "PrimaryButton";