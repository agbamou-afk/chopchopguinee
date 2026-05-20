import { useCallback, useEffect, useRef, useState } from "react";
import { buildDemoMission } from "@/lib/missions/demoMissions";
import type { Mission, MissionType } from "@/lib/missions/types";

/** Rotation order — Repas leads so the demo highlights the new pipeline. */
const ROTATION: MissionType[] = [
  "food_delivery",
  "ride",
  "package_delivery",
  "marketplace_delivery",
];

const rand = (min: number, max: number) =>
  Math.floor(Math.random() * (max - min + 1)) + min;

/**
 * Demo-only dispatch queue. Lives entirely in memory: it never touches the
 * database and never interacts with the real ride/offer queue. When the
 * driver starts demo mode, this hook rotates through Repas / Moto / Marché /
 * Colis offers as `pending` missions which the popup layer renders.
 *
 * Lifecycle:
 *  - start()    -> rotation on, first popup queued shortly
 *  - accept()   -> moves pending into `active`, pauses rotation
 *  - decline()  -> drops pending, schedules next popup
 *  - close()    -> clears active, resumes rotation if still on
 *  - stop()     -> clears everything
 */
export function useDemoMissionQueue() {
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

  const start = useCallback(() => {
    setRotating(true);
    idxRef.current = 0;
    queueNext(rand(1500, 2500));
  }, [queueNext]);

  const stop = useCallback(() => {
    setRotating(false);
    setPending(null);
    clearTimer();
  }, [clearTimer]);

  const accept = useCallback(() => {
    if (!pending) return;
    clearTimer();
    setActive({ ...pending, state: "heading_to_pickup", courier_id: "demo-courier" });
    setPending(null);
  }, [pending, clearTimer]);

  const decline = useCallback(() => {
    setPending(null);
    if (rotating && !active) queueNext(rand(3500, 5500));
  }, [rotating, active, queueNext]);

  const closeActive = useCallback(() => {
    setActive(null);
    if (rotating) queueNext(rand(2500, 4500));
  }, [rotating, queueNext]);

  // Pause rotation while a mission is active; clean up on unmount.
  useEffect(() => {
    if (active) clearTimer();
    return () => clearTimer();
  }, [active, clearTimer]);

  return {
    rotating,
    pending,
    active,
    setActive,
    start,
    stop,
    accept,
    decline,
    closeActive,
  };
}