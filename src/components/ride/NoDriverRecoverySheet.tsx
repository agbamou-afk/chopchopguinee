import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { RotateCcw, Bike, X } from "lucide-react";
import { rideModeLabel } from "@/lib/rides/rideModeLabel";

interface Props {
  open: boolean;
  /** Service the customer was searching for. */
  mode: "moto" | "toktok";
  onOpenChange: (open: boolean) => void;
  /** Search again with the same service. */
  onRetry: () => void;
  /** Switch to the alternative service (Moto <-> Bonbonna). */
  onSwitchMode: (mode: "moto" | "toktok") => void;
}

/**
 * Shown when the 60-second search window closed with no driver.
 * The server has already cancelled the ride, released the reservation in full
 * and charged nothing — this sheet only offers the recovery paths.
 */
export function NoDriverRecoverySheet({ open, mode, onOpenChange, onRetry, onSwitchMode }: Props) {
  const alternative: "moto" | "toktok" = mode === "toktok" ? "moto" : "toktok";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Aucun chauffeur {rideModeLabel(mode)} disponible</DialogTitle>
          <DialogDescription>
            Vos fonds réservés ont été libérés en totalité. Aucun frais ne vous a été facturé.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Button className="w-full h-11 gradient-primary font-semibold" onClick={onRetry}>
            <RotateCcw className="w-4 h-4 mr-2" />
            Réessayer en {rideModeLabel(mode)}
          </Button>
          <Button variant="outline" className="w-full h-11" onClick={() => onSwitchMode(alternative)}>
            <Bike className="w-4 h-4 mr-2" />
            Essayer en {rideModeLabel(alternative)}
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