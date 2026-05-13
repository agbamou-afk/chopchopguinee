import { AlertCircle } from "lucide-react";
import { SecondaryButton } from "@/components/ui/SecondaryButton";
import { cn } from "@/lib/utils";

interface ErrorStateProps {
  title?: string;
  description?: string;
  onRetry?: () => void;
  retryLabel?: string;
  className?: string;
}

export function ErrorState({
  title = "Une erreur est survenue",
  description = "Vérifie ta connexion et réessaie.",
  onRetry,
  retryLabel = "Réessayer",
  className,
}: ErrorStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center text-center px-6 py-10 gap-3",
        className,
      )}
    >
      <div className="w-14 h-14 rounded-2xl bg-brand-red-muted flex items-center justify-center">
        <AlertCircle className="w-6 h-6 text-destructive" />
      </div>
      <div className="space-y-1">
        <h3 className="text-base font-semibold text-foreground">{title}</h3>
        <p className="text-sm text-muted-foreground max-w-xs">{description}</p>
      </div>
      {onRetry && (
        <div className="pt-2 w-full max-w-[200px]">
          <SecondaryButton onClick={onRetry}>{retryLabel}</SecondaryButton>
        </div>
      )}
    </div>
  );
}