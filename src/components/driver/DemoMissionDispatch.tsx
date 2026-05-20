import { createContext, useContext, type ReactNode } from "react";
import { Sparkles, Square, Radar } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { MissionOfferPopup } from "./MissionOfferPopup";
import { DemoActiveMissionCard } from "./DemoActiveMissionCard";
import { MISSION_IDENTITY } from "@/lib/missions/pipelines";
import { useDemoMissionQueue } from "@/hooks/useDemoMissionQueue";

type DemoQueue = ReturnType<typeof useDemoMissionQueue>;
const Ctx = createContext<DemoQueue | null>(null);

/**
 * Provides the demo mission queue + always-on overlay. Mount once near the
 * top of DriverHome so the popup layer is never unmounted by sibling state
 * changes (e.g. real ride queue toggling). Children can read the queue via
 * useDemoDispatch() to show start/stop UI.
 */
export function DemoMissionDispatchProvider({ children }: { children: ReactNode }) {
  const q = useDemoMissionQueue();

  return (
    <Ctx.Provider value={q}>
      {children}

      {/* Always-mounted popup layer — fixed overlay, survives sibling changes. */}
      <MissionOfferPopup
        mission={q.pending}
        onAccept={() => {
          q.accept();
          toast.success("Mission acceptée (démo)");
        }}
        onDecline={() => q.decline()}
        timeoutSec={25}
        demo
      />

      {q.active && (
        <div className="fixed inset-x-0 bottom-0 z-[50] px-3 pb-4 pointer-events-none">
          <div className="max-w-md mx-auto pointer-events-auto space-y-2">
            <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
              Mission démo · {MISSION_IDENTITY[q.active.type].label}
            </h3>
            <DemoActiveMissionCard
              mission={q.active}
              onChange={q.setActive}
              onClose={q.closeActive}
            />
          </div>
        </div>
      )}
    </Ctx.Provider>
  );
}

export function useDemoDispatch(): DemoQueue {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useDemoDispatch must be used inside DemoMissionDispatchProvider");
  return ctx;
}

/**
 * Inline control surface for the dashboard: a "Lancer une mission démo"
 * button when idle, or a "Démo en cours" banner with stop control while
 * rotating. Safe to hide/show based on dashboard state — the popup overlay
 * lives in the provider above and is unaffected.
 */
export function DemoMissionLauncher() {
  const q = useDemoDispatch();

  if (q.active) return null;

  if (!q.rotating) {
    return (
      <Button
        onClick={() => {
          q.start();
          toast("Mode démo activé", {
            description: "Les missions vont défiler automatiquement.",
          });
        }}
        className="w-full h-12 gradient-primary gap-2"
      >
        <Sparkles className="w-4 h-4" />
        Lancer une mission démo
      </Button>
    );
  }

  return (
    <div className="flex items-center justify-between gap-2 rounded-2xl border border-primary/30 bg-primary/5 px-3 py-2">
      <span className="inline-flex items-center gap-2 text-[11px] font-semibold text-primary">
        <Radar className="w-3.5 h-3.5 animate-pulse" />
        Démo en cours · missions automatiques
      </span>
      <Button
        size="sm"
        variant="ghost"
        className="h-8 px-2 gap-1 text-muted-foreground hover:text-destructive"
        onClick={() => {
          q.stop();
          toast("Mode démo arrêté");
        }}
      >
        <Square className="w-3.5 h-3.5" />
        Arrêter
      </Button>
    </div>
  );
}