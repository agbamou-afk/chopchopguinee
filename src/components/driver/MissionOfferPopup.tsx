import { memo, useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Clock, ShieldCheck } from "lucide-react";
import { MissionRequestCard } from "./MissionRequestCard";
import { MISSION_IDENTITY } from "@/lib/missions/pipelines";
import type { Mission } from "@/lib/missions/types";
import { useLowDataMode } from "@/hooks/useLowDataMode";

interface Props {
  mission: Mission | null;
  onAccept: (id: string) => void;
  onDecline: (id: string) => void;
  timeoutSec?: number;
  /** When true, label the popup as a demo so operators can tell it apart. */
  demo?: boolean;
}

/**
 * Centered, type-aware mission offer popup. Mirrors the visual treatment of
 * the ride IncomingRequestIsland (countdown bar, glassy card, soft wash) but
 * uses MissionRequestCard so the copy / accent / trust hint vary by mission
 * type (Course Moto, Livraison Repas, Livraison Marché, Envoyer colis).
 *
 * No "Nouvelle course · client vérifié" — the eyebrow comes from
 * MISSION_IDENTITY so each type reads correctly.
 */
export function MissionOfferPopup({ mission, onAccept, onDecline, timeoutSec = 25, demo }: Props) {
  const [remaining, setRemaining] = useState(timeoutSec);
  const { low } = useLowDataMode();

  useEffect(() => {
    if (!mission) return;
    setRemaining(timeoutSec);
    const id = window.setInterval(() => {
      setRemaining((r) => {
        if (r <= 1) {
          window.clearInterval(id);
          onDecline(mission.id);
          return 0;
        }
        return r - 1;
      });
    }, 1000);
    return () => window.clearInterval(id);
  }, [mission, timeoutSec, onDecline]);

  const urgent = remaining <= 5;
  const identity = mission ? MISSION_IDENTITY[mission.type] : null;

  return (
    <AnimatePresence>
      {mission && identity && (
        <>
          {!low && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.3, ease: "easeOut" }}
              className="fixed inset-0 z-[55] pointer-events-none"
              style={{
                background:
                  "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 0%, rgba(0,0,0,0.06) 55%, rgba(0,0,0,0.10) 100%)",
              }}
              aria-hidden
            />
          )}
          <div className="fixed inset-0 z-[60] flex items-center justify-center pointer-events-none px-3">
            <motion.div
              key={mission.id}
              initial={{ opacity: 0, scale: 0.96, y: 6 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: 6 }}
              transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
              role="dialog"
              aria-label={`Nouvelle mission ${identity.label}`}
              className={`w-[min(360px,100%)] pointer-events-auto rounded-2xl bg-card/97 backdrop-blur-md overflow-hidden shadow-island border ${
                urgent ? "border-destructive/50 ring-2 ring-destructive/25" : identity.accent.border
              } transition-colors duration-200`}
            >
              <CountdownBar id={mission.id} duration={timeoutSec} urgent={urgent} />

              <div className="flex items-center justify-between px-4 pt-3">
                <span className={`inline-flex items-center gap-1.5 text-[10.5px] font-bold uppercase tracking-[0.18em] ${identity.accent.chipText}`}>
                  <ShieldCheck className="w-3 h-3" />
                  Nouvelle mission · {identity.label}
                  {demo && <span className="ml-1 text-muted-foreground">· démo</span>}
                </span>
                <span
                  className={`flex items-center gap-1 px-2 py-1 rounded-full font-semibold tabular-nums text-[11px] ${
                    urgent ? "bg-destructive/15 text-destructive" : "bg-muted text-muted-foreground"
                  }`}
                >
                  <Clock className="w-3 h-3" />
                  {remaining}s
                </span>
              </div>

              <div className="p-3 pt-2">
                <MissionRequestCard
                  mission={mission}
                  onAccept={onAccept}
                  onDecline={onDecline}
                />
              </div>
            </motion.div>
          </div>
        </>
      )}
    </AnimatePresence>
  );
}

const CountdownBar = memo(function CountdownBar({
  id,
  duration,
  urgent,
}: {
  id: string;
  duration: number;
  urgent: boolean;
}) {
  return (
    <div className="h-1 bg-muted/60">
      <motion.div
        key={id}
        initial={{ width: "100%" }}
        animate={{ width: "0%" }}
        transition={{ duration, ease: "linear" }}
        className={`h-full ${urgent ? "bg-destructive" : "gradient-primary"}`}
      />
    </div>
  );
});