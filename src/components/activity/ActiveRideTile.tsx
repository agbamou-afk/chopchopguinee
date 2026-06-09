import { useEffect, useState } from "react";
import { Bike, ChevronRight, Search, MapPin, Navigation } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

interface ActiveRide {
  id: string;
  status: string;
  mode: string;
  driver_id: string | null;
  metadata: Record<string, unknown> | null;
}

/**
 * "Course en cours" tile shown at the top of Dernière activité whenever the
 * customer has an in-flight ride. Tapping it dispatches `cc:open-active-ride`,
 * which Index handles by reopening the realtime trip dashboard. This is the
 * primary re-entry point after the user minimises the dashboard.
 */
export function ActiveRideTile() {
  const { user } = useAuth();
  const [ride, setRide] = useState<ActiveRide | null>(null);

  useEffect(() => {
    if (!user) {
      setRide(null);
      return;
    }
    let alive = true;
    const fetchActive = async () => {
      // Recent in-flight rides only; ignore stale pending rides older than 30 min
      // so a forgotten un-matched request never traps the UI.
      const cutoff = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const { data } = await supabase
        .from("rides")
        .select("id,status,mode,driver_id,metadata,created_at")
        .eq("client_id", user.id)
        .in("status", ["pending", "in_progress"])
        .gte("created_at", cutoff)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!alive) return;
      if (!data) {
        setRide(null);
        return;
      }
      const ageMs = Date.now() - new Date((data as any).created_at).getTime();
      if (data.status === "pending" && !data.driver_id && ageMs > 30 * 60 * 1000) {
        setRide(null);
        return;
      }
      setRide(data as ActiveRide);
    };
    fetchActive();
    const channel = supabase
      .channel(`active-ride-tile-${user.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "rides", filter: `client_id=eq.${user.id}` },
        () => fetchActive(),
      )
      .subscribe();
    return () => {
      alive = false;
      supabase.removeChannel(channel);
    };
  }, [user]);

  if (!ride) return null;

  const meta = (ride.metadata ?? {}) as Record<string, unknown>;
  const phase = (meta.phase as string | undefined) ?? "approach";
  const vehicleLabel = ride.mode === "toktok" ? "TokTok" : "Moto";
  const { sub, Icon, accent } = (() => {
    if (ride.status === "pending" && !ride.driver_id) {
      return { sub: "Recherche d'un chauffeur…", Icon: Search, accent: "bg-amber-500" };
    }
    if (phase === "arrived") {
      return { sub: "Chauffeur arrivé · montrez votre code", Icon: MapPin, accent: "bg-emerald-500" };
    }
    if (phase === "on_trip" || ride.status === "in_progress") {
      return { sub: "Course en cours", Icon: Navigation, accent: "bg-primary" };
    }
    return { sub: "Votre chauffeur arrive", Icon: Bike, accent: "bg-primary" };
  })();

  const open = () => {
    window.dispatchEvent(
      new CustomEvent("cc:open-active-ride", { detail: { rideId: ride.id } }),
    );
  };

  return (
    <button
      type="button"
      onClick={open}
      className="w-full text-left rounded-2xl border border-primary/30 bg-gradient-to-br from-primary/10 via-primary/5 to-transparent p-4 shadow-card flex items-center gap-3 hover:border-primary/50 transition-colors mb-4"
      aria-label="Ouvrir votre course en cours"
    >
      <div className="relative h-11 w-11 shrink-0">
        <span className={`absolute inset-0 rounded-full ${accent} opacity-20 animate-ping`} />
        <div className={`absolute inset-0 rounded-full ${accent} opacity-90 flex items-center justify-center`}>
          <Icon className="h-5 w-5 text-primary-foreground" />
        </div>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-[11px] uppercase tracking-wider font-semibold text-primary">
          Course en cours · {vehicleLabel}
        </p>
        <p className="text-sm font-semibold truncate">{sub}</p>
        <p className="text-xs text-muted-foreground truncate">
          Touchez pour rouvrir le suivi en direct
        </p>
      </div>
      <ChevronRight className="h-5 w-5 text-muted-foreground shrink-0" />
    </button>
  );
}