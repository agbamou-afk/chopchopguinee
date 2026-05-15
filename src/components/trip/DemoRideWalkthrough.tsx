import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Search, CheckCircle2, Car, MapPin, Navigation, Phone, User, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ClientTripReceipt } from "./ClientTripReceipt";
import { formatGNF } from "@/lib/format";
import { ChopMap } from "@/components/map/ChopMap";

type Phase =
  | "searching"
  | "found"
  | "enroute"
  | "arrived"
  | "in_progress"
  | "completed";

interface Props {
  mode: "moto" | "toktok" | "food";
  fare: number;
  rideId?: string | null;
  onClose: () => void;
}

const TITLES: Record<Props["mode"], string> = {
  moto: "Moto · Démo",
  toktok: "TokTok · Démo",
  food: "Repas · Démo",
};

const PHASE_COPY: Record<Phase, string> = {
  searching: "Recherche d'un chauffeur…",
  found: "Chauffeur trouvé",
  enroute: "Chauffeur en route",
  arrived: "Chauffeur arrivé au point de prise en charge",
  in_progress: "Course en cours",
  completed: "Course terminée",
};

/**
 * Presentation-only walkthrough for the demo client account.
 * Every phase has a visible CTA so the demo never traps the user
 * in a waiting state. Does not touch the live ride lifecycle.
 */
export function DemoRideWalkthrough({ mode, fare, rideId, onClose }: Props) {
  const [phase, setPhase] = useState<Phase>("searching");

  // Auto-advance from "searching" to "found" after a short beat.
  useEffect(() => {
    if (phase !== "searching") return;
    const t = setTimeout(() => setPhase("found"), 1500);
    return () => clearTimeout(t);
  }, [phase]);

  if (phase === "completed") {
    return (
      <ClientTripReceipt
        rideId={rideId ?? "demo"}
        fareGnf={fare}
        driverName="Demo Driver"
        paymentLabel="Espèces · Démo"
        onClose={onClose}
      />
    );
  }

  const cta = nextCta(phase);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      {/* Header */}
      <div className="gradient-primary px-4 py-3 flex items-center justify-between shrink-0">
        <button
          type="button"
          onClick={onClose}
          aria-label="Fermer"
          className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition"
        >
          <X className="w-5 h-5 text-primary-foreground" />
        </button>
        <div className="flex items-center gap-2 min-w-0">
          <span className="text-primary-foreground text-sm font-semibold truncate">
            {TITLES[mode]}
          </span>
          <span className="inline-flex items-center gap-1 rounded-full bg-white/20 text-primary-foreground text-[10px] font-bold px-2 py-0.5">
            <Sparkles className="w-3 h-3" /> Mode démo
          </span>
        </div>
        <div className="w-9" />
      </div>

      {/* Live map background (demo, non-interactive) */}
      <div className="flex-1 relative overflow-hidden">
        <ChopMap className="absolute inset-0" interactive={false} />
        <div className="absolute inset-0 bg-background/10 pointer-events-none" />
        <PhaseBadge phase={phase} />

        {/* Pickup confirmation overlay */}
        <AnimatePresence>
          {phase === "arrived" && (
            <motion.div
              key="pickup"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              className="absolute left-4 right-4 top-20"
            >
              <div className="rounded-2xl bg-card shadow-card border border-border p-4">
                <p className="text-xs uppercase tracking-wider text-muted-foreground">
                  Confirmation pickup
                </p>
                <p className="text-sm font-semibold mt-1">
                  Votre chauffeur est sur place. Confirmez la prise en charge pour démarrer.
                </p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Bottom card */}
      <div className="bg-card border-t border-border p-4 space-y-3 shrink-0">
        <DriverCard phase={phase} fare={fare} />

        <Button
          onClick={() => setPhase(cta.next)}
          disabled={phase === "searching"}
          className="w-full h-12 gradient-primary font-semibold text-primary-foreground"
        >
          {cta.label}
        </Button>

        <p className="text-[11px] text-center text-muted-foreground">
          Démo guidée · aucun chauffeur réel n'est sollicité
        </p>
      </div>
    </motion.div>
  );
}

function nextCta(phase: Phase): { label: string; next: Phase } {
  switch (phase) {
    case "searching":
      return { label: "Recherche en cours…", next: "found" };
    case "found":
      return { label: "Continuer la démo", next: "enroute" };
    case "enroute":
      return { label: "Simuler arrivée chauffeur", next: "arrived" };
    case "arrived":
      return { label: "Confirmer pickup démo", next: "in_progress" };
    case "in_progress":
      return { label: "Simuler arrivée destination", next: "completed" };
    default:
      return { label: "Terminer", next: "completed" };
  }
}

function PhaseBadge({ phase }: { phase: Phase }) {
  const Icon =
    phase === "searching" ? Search
    : phase === "found" ? CheckCircle2
    : phase === "enroute" ? Car
    : phase === "arrived" ? MapPin
    : Navigation;
  return (
    <div className="absolute top-4 left-1/2 -translate-x-1/2">
      <motion.div
        key={phase}
        initial={{ y: -10, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="inline-flex items-center gap-2 rounded-full bg-card/90 backdrop-blur px-3 py-1.5 shadow-card border border-border"
      >
        <Icon className="w-4 h-4 text-primary" />
        <span className="text-xs font-semibold text-foreground">{PHASE_COPY[phase]}</span>
      </motion.div>
    </div>
  );
}

function DriverCard({ phase, fare }: { phase: Phase; fare: number }) {
  if (phase === "searching") {
    return (
      <div className="flex items-center gap-3 rounded-xl border border-dashed border-border p-3">
        <div className="w-10 h-10 rounded-full bg-muted animate-pulse" />
        <div className="flex-1 space-y-1">
          <div className="h-3 w-32 bg-muted rounded animate-pulse" />
          <div className="h-2.5 w-24 bg-muted rounded animate-pulse" />
        </div>
        <span className="text-xs font-semibold tabular-nums">{formatGNF(fare)}</span>
      </div>
    );
  }
  return (
    <div className="flex items-center gap-3 rounded-xl border border-border bg-card p-3">
      <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
        <User className="w-5 h-5 text-primary" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold leading-tight truncate">Demo Driver</p>
        <p className="text-[11px] text-muted-foreground leading-tight">
          Moto · Plaque DEMO-001 · ⭐ 4.9
        </p>
      </div>
      <button
        type="button"
        aria-label="Appeler"
        className="p-2 rounded-full bg-primary/10 text-primary"
        onClick={(e) => e.preventDefault()}
      >
        <Phone className="w-4 h-4" />
      </button>
      <span className="text-xs font-semibold tabular-nums">{formatGNF(fare)}</span>
    </div>
  );
}