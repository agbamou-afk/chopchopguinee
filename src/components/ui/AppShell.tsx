import { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * AppShell — consistent mobile page wrapper.
 * - Caps width at max-w-md (matches the rest of the app)
 * - Adds safe bottom padding so content never sits under BottomNav (h ~64px + scanner FAB)
 */
interface AppShellProps {
  children: ReactNode;
  className?: string;
  withBottomNav?: boolean;
  background?: "default" | "muted";
}

export function AppShell({
  children,
  className,
  withBottomNav = true,
  background = "default",
}: AppShellProps) {
  return (
    <div
      className={cn(
        "min-h-screen w-full",
        background === "muted" ? "bg-muted/40" : "bg-app-conakry",
      )}
    >
      <div
        className={cn(
          "max-w-md mx-auto",
          withBottomNav ? "pb-28" : "pb-6",
          className,
        )}
      >
        {children}
      </div>
    </div>
  );
}