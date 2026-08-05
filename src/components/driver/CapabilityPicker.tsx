import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  ALL_CAPABILITIES,
  CAPABILITY_LABEL,
  type DriverCapability,
} from "@/lib/missions/capabilities";

interface CapabilityPickerProps {
  userId: string;
  capabilities: string[];
  onChange?: (next: string[]) => void;
}

/**
 * Read-only summary of the mission types a driver is allowed to accept.
 *
 * Capabilities are granted by an operations/god admin
 * (`admin_set_driver_capability`). Drivers cannot grant themselves new ones,
 * and removing one from the client would be irreversible from their side, so
 * this surface reports the truth instead of offering a toggle that lies.
 */
export function CapabilityPicker({ capabilities }: CapabilityPickerProps) {
  const granted = ALL_CAPABILITIES.filter((c) =>
    capabilities.includes(c),
  ) as DriverCapability[];

  return (
    <div className="rounded-2xl bg-card border border-border/50 shadow-card p-3">
      <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground mb-2">
        Mes capacités
      </p>
      <div className="flex flex-wrap gap-1.5">
        {granted.length === 0 && (
          <p className="text-[11.5px] text-muted-foreground">
            Aucune capacité attribuée pour le moment.
          </p>
        )}
        {granted.map((cap) => (
          <span
            key={cap}
            className={cn(
              "inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold border",
              "bg-primary/10 border-primary/40 text-primary",
            )}
          >
            <Check className="w-3 h-3" />
            {CAPABILITY_LABEL[cap]}
          </span>
        ))}
      </div>
      <p className="mt-2 text-[11px] text-muted-foreground leading-snug">
        Les capacités sont attribuées par CHOPCHOP. Pour en ajouter une (colis, livraisons),
        contactez le support.
      </p>
    </div>
  );
}