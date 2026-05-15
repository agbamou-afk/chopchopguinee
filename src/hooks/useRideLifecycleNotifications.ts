import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { notifications } from "@/lib/notifications";
import type { RideRealtime } from "@/hooks/useRideRealtime";

export type RideLifecycleEvent =
  | "driver_assigned"
  | "driver_arriving"
  | "ride_started"
  | "ride_completed"
  | "ride_cancelled";

type Role = "client" | "driver";

const COPY: Record<RideLifecycleEvent, Record<Role, { title: string; body: string; tone: "success" | "error" | "info" }>> = {
  driver_assigned: {
    client: { title: "Chauffeur trouvé", body: "Un chauffeur a accepté votre course.", tone: "success" },
    driver: { title: "Course attribuée", body: "Vous avez accepté une nouvelle course.", tone: "success" },
  },
  driver_arriving: {
    client: { title: "Chauffeur en approche", body: "Votre chauffeur arrive au point de départ.", tone: "info" },
    driver: { title: "Bientôt sur place", body: "Vous approchez du point de départ du client.", tone: "info" },
  },
  ride_started: {
    client: { title: "Course commencée", body: "Bonne route ! Suivez votre trajet en direct.", tone: "info" },
    driver: { title: "Course démarrée", body: "Trajet en cours.", tone: "info" },
  },
  ride_completed: {
    client: { title: "Arrivé à destination", body: "Paiement confirmé. Merci d'avoir utilisé CHOP CHOP.", tone: "success" },
    driver: { title: "Course terminée", body: "Paiement encaissé et crédité à votre portefeuille.", tone: "success" },
  },
  ride_cancelled: {
    client: { title: "Course annulée", body: "Votre course a été annulée.", tone: "error" },
    driver: { title: "Course annulée", body: "La course a été annulée.", tone: "error" },
  },
};

function dedup(eventId: string): boolean {
  try {
    const KEY = "chopchop:ride-events:seen";
    const raw = sessionStorage.getItem(KEY);
    const set = new Set<string>(raw ? (JSON.parse(raw) as string[]) : []);
    if (set.has(eventId)) return true;
    set.add(eventId);
    sessionStorage.setItem(KEY, JSON.stringify(Array.from(set).slice(-300)));
    return false;
  } catch {
    return false;
  }
}

function fire(event: RideLifecycleEvent, role: Role, rideId: string) {
  const eventId = `ride:${rideId}:${event}`;
  if (dedup(eventId)) return;
  const c = COPY[event][role];
  if (c.tone === "success") toast.success(c.title, { description: c.body, id: eventId });
  else if (c.tone === "error") toast.error(c.title, { description: c.body, id: eventId });
  else toast(c.title, { description: c.body, id: eventId });
  notifications.push({
    kind: "ride",
    title: c.title,
    body: c.body,
    // Deep-link the ride alert into the timeline so the user lands on the
    // matching ride entry (and can open the receipt) in one tap.
    link: "/?tab=orders",
  });
}

/**
 * Watches a ride row and fires exactly one notification sequence per
 * lifecycle transition (driver_assigned, driver_arriving, ride_started,
 * ride_completed, ride_cancelled). Mount on both the client and driver
 * trip screens so they stay synchronized.
 */
export function useRideLifecycleNotifications(
  ride: RideRealtime | null,
  role: Role,
) {
  // `prev` is seeded from the first observed ride snapshot — never null —
  // so reopening or refreshing a ride mid-flight does NOT re-fire toasts
  // for transitions that already happened before mount.
  const prev = useRef<{
    status: string | null;
    driverId: string | null;
    arriving: boolean;
    initialized: boolean;
  }>({ status: null, driverId: null, arriving: false, initialized: false });

  useEffect(() => {
    if (!ride) return;
    const status = ride.status;
    const driverId = ride.driver_id ?? null;
    const arriving = Boolean(
      (ride.metadata as Record<string, unknown> | null)?.driver_arriving,
    );
    const last = prev.current;

    // First observation: snapshot without firing. We only want to notify on
    // genuine transitions, not on catch-up after refresh/reconnect/restore.
    if (!last.initialized) {
      prev.current = { status, driverId, arriving, initialized: true };
      return;
    }

    // Terminal states are mutually exclusive — never fire the other one
    // afterwards even if a stale event sneaks in.
    const wasTerminal = last.status === "completed" || last.status === "cancelled";

    if (!wasTerminal && driverId && !last.driverId) {
      fire("driver_assigned", role, ride.id);
    }
    if (!wasTerminal && arriving && !last.arriving && status !== "in_progress" && status !== "completed") {
      fire("driver_arriving", role, ride.id);
    }
    if (!wasTerminal && status === "in_progress" && last.status !== "in_progress") {
      fire("ride_started", role, ride.id);
    }
    if (status === "completed" && last.status !== "completed" && last.status !== "cancelled") {
      fire("ride_completed", role, ride.id);
    }
    if (status === "cancelled" && last.status !== "cancelled" && last.status !== "completed") {
      fire("ride_cancelled", role, ride.id);
    }

    prev.current = { status, driverId, arriving, initialized: true };
  }, [ride, role]);
}