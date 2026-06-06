import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export interface NearbyDriver {
  driver_ref: string;
  approx_lat: number;
  approx_lng: number;
  distance_m: number;
  vehicle_type: string | null;
  heading: number | null;
  last_seen_at: string;
}

interface Options {
  lat: number | null;
  lng: number | null;
  radiusM?: number;
  vehicleType?: "moto" | "toktok" | null;
  refreshMs?: number;
  enabled?: boolean;
}

/**
 * Privacy-safe nearby driver discovery for customers.
 * Uses get_nearby_available_drivers RPC — only approved + online + fresh drivers,
 * with ~110m rounded coordinates and an opaque per-hour driver_ref.
 */
export function useNearbyAvailableDrivers({
  lat, lng, radiusM = 3000, vehicleType = null, refreshMs = 20000, enabled = true,
}: Options) {
  const [drivers, setDrivers] = useState<NearbyDriver[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled || lat == null || lng == null) {
      setDrivers([]);
      return;
    }
    let alive = true;
    const load = async () => {
      setLoading(true);
      const { data, error } = await supabase.rpc("get_nearby_available_drivers", {
        p_lat: lat,
        p_lng: lng,
        p_radius_m: radiusM,
        p_vehicle_type: vehicleType,
        p_limit: 25,
      });
      if (!alive) return;
      if (error) {
        setError(error.message);
        setDrivers([]);
      } else {
        setError(null);
        setDrivers((data ?? []) as NearbyDriver[]);
      }
      setLoading(false);
    };
    load();
    const id = window.setInterval(load, refreshMs);
    return () => { alive = false; window.clearInterval(id); };
  }, [lat, lng, radiusM, vehicleType, refreshMs, enabled]);

  return { drivers, loading, error };
}