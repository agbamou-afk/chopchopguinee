import { ReactNode } from "react";
import { LucideIcon, Inbox } from "lucide-react";
import { cn } from "@/lib/utils";

interface EmptyStateProps {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: ReactNode;
  className?: string;
}

export function EmptyState({
  icon: Icon = Inbox,
  title,
  description,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center text-center px-6 py-12 gap-3.5",
        className,
      )}
    >
      <div className="relative w-16 h-16 rounded-[20px] bg-gradient-to-br from-primary/12 via-secondary/10 to-primary/4 ring-1 ring-primary/10 flex items-center justify-center">
        <span className="absolute inset-0 rounded-[20px] ring-1 ring-inset ring-white/40" aria-hidden />
        <Icon className="w-6 h-6 text-primary" strokeWidth={1.75} />
      </div>
      <div className="space-y-1.5">
        <h3 className="text-base font-bold text-foreground tracking-tight">{title}</h3>
        {description && (
          <p className="text-[13px] text-muted-foreground max-w-xs leading-relaxed">{description}</p>
        )}
      </div>
      {action && <div className="pt-2">{action}</div>}
    </div>
  );
}