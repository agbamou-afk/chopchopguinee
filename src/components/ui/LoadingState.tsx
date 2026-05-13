import { Skeleton } from "@/components/ui/skeleton";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

interface LoadingStateProps {
  variant?: "spinner" | "list" | "cards";
  rows?: number;
  label?: string;
  className?: string;
}

export function LoadingState({
  variant = "spinner",
  rows = 3,
  label,
  className,
}: LoadingStateProps) {
  if (variant === "spinner") {
    return (
      <div className={cn("flex flex-col items-center justify-center gap-2 py-10", className)}>
        <Loader2 className="w-5 h-5 text-primary animate-spin" />
        {label && <p className="text-xs text-muted-foreground">{label}</p>}
      </div>
    );
  }

  if (variant === "list") {
    return (
      <div className={cn("space-y-3", className)}>
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="flex items-center gap-3 p-3 bg-card rounded-2xl shadow-card">
            <Skeleton className="w-10 h-10 rounded-xl" />
            <div className="flex-1 space-y-2">
              <Skeleton className="h-3 w-1/2" />
              <Skeleton className="h-3 w-1/3" />
            </div>
          </div>
        ))}
      </div>
    );
  }

  // cards
  return (
    <div className={cn("grid grid-cols-2 gap-3", className)}>
      {Array.from({ length: rows * 2 }).map((_, i) => (
        <div key={i} className="bg-card rounded-2xl shadow-card overflow-hidden">
          <Skeleton className="h-28 w-full rounded-none" />
          <div className="p-3 space-y-2">
            <Skeleton className="h-3 w-3/4" />
            <Skeleton className="h-3 w-1/2" />
          </div>
        </div>
      ))}
    </div>
  );
}