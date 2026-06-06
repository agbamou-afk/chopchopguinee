import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import type { FoodRestaurant } from "@/lib/repas/types";

export interface MerchantStore {
  id: string;
  owner_user_id: string;
  name: string;
  slug: string;
  category: string | null;
  avatar_url: string | null;
  cover_url: string | null;
  district: string | null;
  status: string;
  delivery_available: boolean;
  choppay_enabled: boolean;
  verification_state: string;
  onboarding_status?: string;
  rejection_reason?: string | null;
}

export interface MerchantIdentity {
  loading: boolean;
  store: MerchantStore | null;
  restaurant: FoodRestaurant | null;
  hasAny: boolean;
  refresh: () => Promise<void>;
}

/**
 * Resolves whether the current authed user owns a Marché store and/or a
 * Repas restaurant. Used to gate the merchant operations hub.
 */
export function useMerchantIdentity(): MerchantIdentity {
  const { user } = useAuth();
  const [store, setStore] = useState<MerchantStore | null>(null);
  const [restaurant, setRestaurant] = useState<FoodRestaurant | null>(null);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    if (!user) {
      setStore(null);
      setRestaurant(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    const [{ data: s }, { data: r }] = await Promise.all([
      (supabase as any)
        .from("merchant_stores")
        .select("*")
        .eq("owner_user_id", user.id)
        .maybeSingle(),
      (supabase as any)
        .from("food_restaurants")
        .select("*")
        .eq("owner_user_id", user.id)
        .maybeSingle(),
    ]);
    setStore((s ?? null) as MerchantStore | null);
    setRestaurant((r ?? null) as FoodRestaurant | null);
    setLoading(false);
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  return {
    loading,
    store,
    restaurant,
    hasAny: !!(store || restaurant),
    refresh: load,
  };
}