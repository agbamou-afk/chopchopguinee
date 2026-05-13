import { ReactNode } from "react";
import { ChevronLeft } from "lucide-react";
import { cn } from "@/lib/utils";

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  onBack?: () => void;
  right?: ReactNode;
  sticky?: boolean;
  className?: string;
}

export function PageHeader({
  title,
  subtitle,
  onBack,
  right,
  sticky = false,
  className,
}: PageHeaderProps) {
  return (
    <header
      className={cn(
        "flex items-center gap-3 px-4 py-3 bg-background",
        sticky && "sticky top-0 z-30 border-b border-border/60",
        className,
      )}
    >
      {onBack && (
        <button
          onClick={onBack}
          aria-label="Retour"
          className="w-9 h-9 -ml-1 rounded-xl flex items-center justify-center hover:bg-muted active:scale-95 transition"
        >
          <ChevronLeft className="w-5 h-5 text-foreground" />
        </button>
      )}
      <div className="flex-1 min-w-0">
        <h1 className="text-base font-semibold text-foreground truncate leading-tight">
          {title}
        </h1>
        {subtitle && (
          <p className="text-xs text-muted-foreground truncate leading-tight">
            {subtitle}
          </p>
        )}
      </div>
      {right && <div className="shrink-0 flex items-center gap-2">{right}</div>}
    </header>
  );
}