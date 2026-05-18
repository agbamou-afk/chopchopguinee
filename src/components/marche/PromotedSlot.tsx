import { Megaphone } from "lucide-react";

// Visually reserved promoted slot — not an active ad.
// Used to interleave the listing grid every ~5–6 cards.
export function PromotedSlot() {
  return (
    <div
      aria-hidden="true"
      className="rounded-2xl border border-dashed border-border/70 bg-card/60 p-3 flex flex-col items-center justify-center text-center min-h-[180px]"
    >
      <div className="w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center mb-2">
        <Megaphone className="w-4 h-4 text-primary" />
      </div>
      <p className="text-[11px] font-semibold text-foreground leading-tight">
        Emplacement sponsorisé
      </p>
      <p className="text-[10px] text-muted-foreground mt-0.5 leading-tight">
        Bientôt disponible pour les boutiques
      </p>
    </div>
  );
}