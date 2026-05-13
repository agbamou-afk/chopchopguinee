import { InputHTMLAttributes, forwardRef } from "react";
import { Search, X } from "lucide-react";
import { cn } from "@/lib/utils";

interface SearchBarProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "onChange"> {
  value?: string;
  onValueChange?: (v: string) => void;
  onClear?: () => void;
  containerClassName?: string;
}

export const SearchBar = forwardRef<HTMLInputElement, SearchBarProps>(
  ({ className, containerClassName, value, onValueChange, onClear, placeholder = "Rechercher…", ...props }, ref) => {
    return (
      <div
        className={cn(
          "flex items-center gap-2 px-4 h-12 bg-card rounded-xl shadow-card",
          containerClassName,
        )}
      >
        <Search className="w-4 h-4 text-muted-foreground shrink-0" />
        <input
          ref={ref}
          value={value}
          onChange={(e) => onValueChange?.(e.target.value)}
          placeholder={placeholder}
          className={cn(
            "flex-1 bg-transparent text-sm text-foreground placeholder:text-muted-foreground outline-none",
            className,
          )}
          {...props}
        />
        {value && (
          <button
            type="button"
            onClick={() => {
              onValueChange?.("");
              onClear?.();
            }}
            aria-label="Effacer"
            className="w-6 h-6 rounded-full flex items-center justify-center hover:bg-muted"
          >
            <X className="w-3.5 h-3.5 text-muted-foreground" />
          </button>
        )}
      </div>
    );
  },
);
SearchBar.displayName = "SearchBar";