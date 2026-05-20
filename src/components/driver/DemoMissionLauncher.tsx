import { useCallback, useEffect, useRef, useState } from "react";
import { Sparkles, Square, Radar } from "lucide-react";
import { Button } from "@/components/ui/button";
import { MissionOfferPopup } from "./MissionOfferPopup";
import { DemoActiveMissionCard } from "./DemoActiveMissionCard";
import { buildDemoMission } from "@/lib/missions/demoMissions";
import { type Mission, type MissionType } from "@/lib/missions/types";
import { MISSION_IDENTITY } from "@/lib/missions/pipelines";
import { toast } from "sonner";

/** Rotation order — one of each type cycled in a stable, varied sequence. */
const ROTATION: MissionType[] = [
  "food_delivery",
  "ride",
  "package_delivery",
  "marketplace_delivery",
];

/** Random integer in [min, max]. */
const rand = (min: number, max: number) =>
  Math.floor(Math.random() * (max - min + 1)) + min;

/**
 * Demo-only auto-dispatch. The driver taps "Lancer une mission démo" once;
 * the app then rotates through Repas / Moto / Marché / Colis offers, one at
 * a time, as MissionOfferPopup. Nothing is written to the database.
 *
 * Rules:
 *  - only one popup at a time
 *  - rotation pauses while a demo mission is active
 *  - resumes once the mission is closed
 *  - user can stop the demo at any time via "Arrêter la démo"
 */
export function DemoMissionLauncher() {
  const [rotating, setRotating] = useState(false);
  const [pending, setPending] = useState<Mission | null>(null);
  const [active, setActive] = useState<Mission | null>(null);
  const idxRef = useRef(0);
  const timerRef = useRef<number | null>(null);

  const clearTimer = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const queueNext = useCallback(
    (delayMs: number) => {
      clearTimer();
      timerRef.current = window.setTimeout(() => {
        timerRef.current = null;
        const type = ROTATION[idxRef.current % ROTATION.length];
        idxRef.current += 1;
        setPending(buildDemoMission(type));
      }, delayMs);
    },
    [clearTimer],
  );

  const startRotation = () => {
    if (rotating) return;
    setRotating(true);
    toast("Mode démo activé", {
      description: "Les missions vont défiler automatiquement.",
    });
    // First popup arrives quickly so the demo feels live.
    queueNext(rand(2000, 4000));
  };

  const stopRotation = () => {
    setRotating(false);
    setPending(null);
    clearTimer();
    toast("Mode démo arrêté");
  };

  const handleAccept = (_id: string) => {
    if (!pending) return;
    clearTimer();
    setActive({ ...pending, state: "heading_to_pickup", courier_id: "demo-courier" });
    setPending(null);
    toast.success("Mission acceptée (démo)");
  };

  const handleDecline = (_id: string) => {
    setPending(null);
    if (rotating && !active) {
      queueNext(rand(4000, 6000));
    }
  };

  const closeActive = () => {
    setActive(null);
    if (rotating) {
      queueNext(rand(3000, 5000));
    }
  };

  // Pause rotation while a mission is active; cleanup on unmount.
  useEffect(() => {
    if (active) clearTimer();
    return () => clearTimer();
  }, [active, clearTimer]);

  return (
    <div className="space-y-3">
      {!active && !rotating && (
        <Button
          onClick={startRotation}
          className="w-full h-12 gradient-primary gap-2"
        >
          <Sparkles className="w-4 h-4" />
          Lancer une mission démo
        </Button>
      )}

      {rotating && !active && (
        <div className="flex items-center justify-between gap-2 rounded-2xl border border-primary/30 bg-primary/5 px-3 py-2">
          <span className="inline-flex items-center gap-2 text-[11px] font-semibold text-primary">
            <Radar className="w-3.5 h-3.5 animate-pulse" />
            Démo en cours · missions automatiques
          </span>
          <Button
            size="sm"
            variant="ghost"
            className="h-8 px-2 gap-1 text-muted-foreground hover:text-destructive"
            onClick={stopRotation}
          >
            <Square className="w-3.5 h-3.5" />
            Arrêter
          </Button>
        </div>
      )}

      <MissionOfferPopup
        mission={pending}
        onAccept={handleAccept}
        onDecline={handleDecline}
        timeoutSec={25}
        demo
      />

      {active && (
        <section className="space-y-2">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
            Mission démo en cours · {MISSION_IDENTITY[active.type].label}
          </h3>
          <DemoActiveMissionCard
            mission={active}
            onChange={setActive}
            onClose={closeActive}
          />
        </section>
      )}
    </div>
  );
}