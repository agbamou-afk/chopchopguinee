import { Check } from "lucide-react";
import { cn } from "@/lib/utils";

export interface TimelineStep {
  key: string;
  label: string;
  description?: string;
  timestamp?: string;
}

interface StatusTimelineProps {
  steps: TimelineStep[];
  /** index of the currently-active step (0-based). Steps before are "done", after are "pending". */
  currentIndex: number;
  className?: string;
}

export function StatusTimeline({ steps, currentIndex, className }: StatusTimelineProps) {
  return (
    <ol className={cn("relative space-y-5", className)}>
      {steps.map((step, i) => {
        const isDone = i < currentIndex;
        const isActive = i === currentIndex;
        const isLast = i === steps.length - 1;

        return (
          <li key={step.key} className="relative pl-9">
            {/* Vertical connector */}
            {!isLast && (
              <span
                className={cn(
                  "absolute left-3 top-6 bottom-[-1.25rem] w-px",
                  isDone ? "bg-primary" : "bg-border",
                )}
                aria-hidden
              />
            )}
            {/* Bullet */}
            <span
              className={cn(
                "absolute left-0 top-0 w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-semibold",
                isDone && "bg-primary text-primary-foreground",
                isActive && "bg-brand-green-muted text-primary ring-2 ring-primary",
                !isDone && !isActive && "bg-muted text-muted-foreground",
              )}
            >
              {isDone ? <Check className="w-3.5 h-3.5" /> : i + 1}
            </span>
            <div className="space-y-0.5">
              <p
                className={cn(
                  "text-sm font-semibold leading-tight",
                  isActive ? "text-foreground" : isDone ? "text-foreground" : "text-muted-foreground",
                )}
              >
                {step.label}
              </p>
              {step.description && (
                <p className="text-xs text-muted-foreground">{step.description}</p>
              )}
              {step.timestamp && (
                <p className="text-[11px] text-muted-foreground">{step.timestamp}</p>
              )}
            </div>
          </li>
        );
      })}
    </ol>
  );
}