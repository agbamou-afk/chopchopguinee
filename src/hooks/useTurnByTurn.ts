import { useEffect, useMemo, useRef, useState } from "react";
import { decodePolyline, haversineMeters, type LatLng } from "@/lib/maps/geo";
import type { NormalizedRoute, RouteStep } from "@/lib/maps/providers/types";
import { RoutingService } from "@/lib/maps/RoutingService";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export interface TurnByTurnState {
  route: NormalizedRoute | null;
  currentStep: RouteStep | null;
  nextStep: RouteStep | null;
  stepIndex: number;
  distanceToManeuverM: number | null;
  remainingDistanceM: number;
  remainingDurationS: number;
  offRoute: boolean;
  rerouting: boolean;
}

const OFF_ROUTE_THRESHOLD_M = 60;     // distance from path that triggers reroute
const OFF_ROUTE_CONFIRMS = 3;          // consecutive ticks before we actually reroute
const REROUTE_COOLDOWN_MS = 15_000;
const ADVANCE_RADIUS_M = 30;           // when within this of step end, advance
const SPEAK_FAR_M = 250;
const SPEAK_NEAR_M = 60;

function nearestPointDistance(p: LatLng, path: LatLng[]): number {
  if (path.length === 0) return Infinity;
  let min = Infinity;
  for (const q of path) {
    const d = haversineMeters(p, q);
    if (d < min) min = d;
  }
  return min;
}

function speak(text: string, mute: boolean) {
  if (mute) return;
  if (typeof window === "undefined" || !("speechSynthesis" in window)) return;
  try {
    const u = new SpeechSynthesisUtterance(text);
    u.lang = "fr-FR";
    u.rate = 1;
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(u);
  } catch {}
}

/**
 * Turn-by-turn engine: tracks driver position vs the active route, advances
 * steps, speaks French cues, and triggers traffic-aware reroutes when the
 * driver leaves the planned path.
 */
export function useTurnByTurn(opts: {
  origin: LatLng | null;
  destination: LatLng | null;
  driverPos: LatLng | null;
  mode?: "driving" | "two_wheeler";
  enabled?: boolean;
  mute?: boolean;
}): TurnByTurnState & { reroute: () => void } {
  const { origin, destination, driverPos, mode = "driving", enabled = true, mute = false } = opts;
  const [route, setRoute] = useState<NormalizedRoute | null>(null);
  const [stepIndex, setStepIndex] = useState(0);
  const [rerouting, setRerouting] = useState(false);
  const [offRoute, setOffRoute] = useState(false);
  const offRouteCount = useRef(0);
  const lastRerouteAt = useRef(0);
  const spokenForStep = useRef<{ idx: number; far: boolean; near: boolean }>({ idx: -1, far: false, near: false });

  const decodedPath = useMemo(() => (route ? decodePolyline(route.polyline) : []), [route]);

  // Initial route fetch
  useEffect(() => {
    if (!enabled || !origin || !destination) return;
    let alive = true;
    setRerouting(true);
    RoutingService.route(origin, destination, mode)
      .then((r) => {
        if (!alive) return;
        setRoute(r); setStepIndex(0); setOffRoute(false); offRouteCount.current = 0;
        spokenForStep.current = { idx: -1, far: false, near: false };
      })
      .catch(() => {})
      .finally(() => { if (alive) setRerouting(false); });
    return () => { alive = false; };
  }, [enabled, origin?.lat, origin?.lng, destination?.lat, destination?.lng, mode]);

  const reroute = () => {
    if (!driverPos || !destination) return;
    if (Date.now() - lastRerouteAt.current < REROUTE_COOLDOWN_MS) return;
    lastRerouteAt.current = Date.now();
    setRerouting(true);
    try { Analytics.track("route.reroute" as any, { metadata: { mode } }); } catch {}
    RoutingService.route(driverPos, destination, mode)
      .then((r) => {
        setRoute(r); setStepIndex(0); setOffRoute(false); offRouteCount.current = 0;
        spokenForStep.current = { idx: -1, far: false, near: false };
        speak("Nouvel itinéraire calculé", mute);
      })
      .catch(() => {})
      .finally(() => setRerouting(false));
  };

  // Tick: advance step / detect off-route / speak cues
  useEffect(() => {
    if (!enabled || !route || !driverPos || route.steps.length === 0) return;

    // Off-route detection
    const distFromPath = nearestPointDistance(driverPos, decodedPath);
    if (distFromPath > OFF_ROUTE_THRESHOLD_M) {
      offRouteCount.current += 1;
      if (offRouteCount.current >= OFF_ROUTE_CONFIRMS) {
        setOffRoute(true);
        reroute();
      }
    } else {
      offRouteCount.current = 0;
      if (offRoute) setOffRoute(false);
    }

    // Advance steps when close to current step end
    const idx = Math.min(stepIndex, route.steps.length - 1);
    const step = route.steps[idx];
    const distToEnd = haversineMeters(driverPos, step.endLocation);
    if (distToEnd < ADVANCE_RADIUS_M && idx < route.steps.length - 1) {
      setStepIndex(idx + 1);
      spokenForStep.current = { idx: idx + 1, far: false, near: false };
      return;
    }

    // Voice cues for the current step
    const s = spokenForStep.current;
    if (s.idx !== idx) spokenForStep.current = { idx, far: false, near: false };
    if (!spokenForStep.current.far && distToEnd < SPEAK_FAR_M && distToEnd > SPEAK_NEAR_M) {
      spokenForStep.current.far = true;
      speak(`Dans ${Math.round(distToEnd)} mètres, ${step.instruction}`, mute);
    }
    if (!spokenForStep.current.near && distToEnd <= SPEAK_NEAR_M) {
      spokenForStep.current.near = true;
      speak(step.instruction, mute);
    }
  }, [driverPos?.lat, driverPos?.lng, route, decodedPath, stepIndex, enabled, mute, offRoute]);

  const currentStep = route?.steps[stepIndex] ?? null;
  const nextStep = route?.steps[stepIndex + 1] ?? null;
  const distanceToManeuverM = currentStep && driverPos
    ? Math.round(haversineMeters(driverPos, currentStep.endLocation))
    : null;
  const remainingDistanceM = route
    ? route.steps.slice(stepIndex).reduce((acc, st) => acc + st.distanceM, 0)
    : 0;
  const remainingDurationS = route
    ? route.steps.slice(stepIndex).reduce((acc, st) => acc + st.durationS, 0)
    : 0;

  return {
    route, currentStep, nextStep, stepIndex,
    distanceToManeuverM, remainingDistanceM, remainingDurationS,
    offRoute, rerouting, reroute,
  };
}