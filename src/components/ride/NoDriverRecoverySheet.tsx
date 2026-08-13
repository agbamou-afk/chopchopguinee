import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { RotateCcw, Bike, X, MapPin } from "lucide-react";
import { rideModeLabel } from "@/lib/rides/rideModeLabel";

/** Persisted server truth for how the cancelled search was going to be paid. */
export type RecoveryPaymentMode = "chop_pay" | "cash" | "unknown";

interface Props {
  open: boolean;
  /** Service the customer was searching for. */
  mode: "moto" | "toktok";
  /** Derived from the cancelled ride row — never guessed from UI state. */
  paymentMode: RecoveryPaymentMode;
  /** Known trip intent, preserved so the customer never retypes the route. */
  pickupLabel?: string | null;
  destLabel?: string | null;
  onOpenChange: (open: boolean) => void;
  /** Search again with the same service (new commitment / new idempotency id). */
  onRetry: () => void;
  /** Open the alternative service booking — never auto-books. */
  onSwitchMode: (mode: "moto" | "toktok") => void;
}

/**
 * Shown when the 60-second search window closed with no driver.
 * The server has already cancelled the ride and charged no cancellation fee.
 * Only a Chop Pay search had funds reserved — a cash search never did, so the
 * copy must not claim a release that did not happen.
 */
export function NoDriverRecoverySheet({
  open, mode, paymentMode, pickupLabel, destLabel, onOpenChange, onRetry, onSwitchMode,
}: Props) {
  const alternative: "moto" | "toktok" = mode === "toktok" ? "moto" : "toktok";
  const title =
    mode === "toktok"
      ? "Aucun Bonbonna disponible pour le moment"
      : "Aucun chauffeur Moto disponible pour le moment";
  const description =
    paymentMode === "chop_pay"
      ? "Votre réservation Chop Pay a été libérée en totalité. Aucun frais d'annulation ne vous a été facturé."
      : "Aucun frais d'annulation ne vous a été facturé.";
  const hasRoute = !!(pickupLabel || destLabel);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {hasRoute && (
          <div className="rounded-lg border border-border bg-muted/40 p-3 text-xs space-y-1">
            <p className="flex items-center gap-2 truncate">
              <MapPin className="w-3.5 h-3.5 shrink-0" />
              <span className="truncate">{pickupLabel ?? "Départ enregistré"}</span>
            </p>
            <p className="flex items-center gap-2 truncate">
              <MapPin className="w-3.5 h-3.5 shrink-0" />
              <span className="truncate">{destLabel ?? "Destination enregistrée"}</span>
            </p>
          </div>
        )}
        <div className="space-y-2">
          <Button className="w-full h-11 gradient-primary font-semibold" onClick={onRetry}>
            <RotateCcw className="w-4 h-4 mr-2" />
            Réessayer
          </Button>
          <Button variant="outline" className="w-full h-11" onClick={() => onSwitchMode(alternative)}>
            <Bike className="w-4 h-4 mr-2" />
            Voir {rideModeLabel(alternative)}
          </Button>
          <Button variant="ghost" className="w-full h-11" onClick={() => onOpenChange(false)}>
            <X className="w-4 h-4 mr-2" />
            Plus tard
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
