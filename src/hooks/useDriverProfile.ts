import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export type DriverPresence = "offline" | "online" | "on_trip";
export type DriverStatus = "pending" | "approved" | "rejected" | "suspended";
export type DriverVehicle = "moto" | "toktok" | "livraison" | "auto";

export interface DriverProfile {
  user_id: string;
  status: DriverStatus;
  vehicle_type: DriverVehicle;
  plate_number: string | null;
  driver_photo_url: string | null;
  id_doc_url: string | null;
  vehicle_photo_url: string | null;
  zones: string[];
  rating: number;
  accept_rate: number;
  cash_debt_gnf: number;
  debt_limit_gnf: number;
  presence: DriverPresence;
  last_seen_at: string | null;
  approved_at: string | null;
  rejected_reason: string | null;
  suspended_reason: string | null;
}

interface State {
  profile: DriverProfile | null;
  loading: boolean;
  error: string | null;
}

export function useDriverProfile() {
  const { user, ready } = useAuth();
  const [state, setState] = useState<State>({ profile: null, loading: true, error: null });

  const refetch = useCallback(async () => {
    if (!user) {
      setState({ profile: null, loading: false, error: null });
      return;
    }
    setState((s) => ({ ...s, loading: true, error: null }));
    const { data, error } = await supabase
      .from("driver_profiles")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();
    if (error) {
      setState({ profile: null, loading: false, error: error.message });
      return;
    }
    setState({ profile: (data as unknown as DriverProfile) ?? null, loading: false, error: null });
  }, [user]);

  useEffect(() => {
    if (!ready) return;
    refetch();
  }, [ready, refetch]);

  return { ...state, refetch, isApproved: state.profile?.status === "approved" };
}