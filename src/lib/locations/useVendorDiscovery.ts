import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export type VendorKind = 'restaurant' | 'store';

export interface DiscoveryVendor {
  id: string;
  name: string;
  slug: string | null;
  district: string | null;
  latitude: number;
  longitude: number;
  kind: VendorKind;
  deliveryAvailable: boolean;
  isOpen: boolean | null; // null for stores (no is_open column)
}

export interface VendorDiscoveryFilters {
  restaurants?: boolean;
  stores?: boolean;
  marche?: boolean; // currently maps to merchant_stores w/ category 'marche'
  openNow?: boolean;
  deliveryOnly?: boolean;
}

/**
 * Customer-mode vendor discovery.
 *
 * Privacy rules enforced here:
 *   - Only vendors with `status='active'` AND explicit lat/lng are returned.
 *   - Private sellers without a public store profile or coordinates are
 *     never exposed as map pins.
 *   - No courier or customer locations are ever fetched here.
 *   - Capped at MAX_RESULTS to avoid clutter and over-fetching.
 *
 * FAILURE DOMAINS ARE SPLIT (Home map remediation): a Repas read failure must
 * never suppress Marché pins, and vice versa. Each vertical has its own
 * try/catch and its own error string; partial supply is always rendered.
 */
const MAX_RESULTS = 50;

export function useVendorDiscovery(
  filters: VendorDiscoveryFilters,
  opts: { enabled?: boolean } = {},
) {
  const { enabled = true } = opts;
  const [vendors, setVendors] = useState<DiscoveryVendor[]>([]);
  const [loading, setLoading] = useState(false);
  const [restaurantError, setRestaurantError] = useState<string | null>(null);
  const [storeError, setStoreError] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled) { setVendors([]); return; }
    let cancelled = false;
    setLoading(true);
    setRestaurantError(null);
    setStoreError(null);
    (async () => {
      const out: DiscoveryVendor[] = [];
      let rErr: string | null = null;
      let sErr: string | null = null;

      if (filters.restaurants !== false) {
        try {
          let q = supabase
            .from('food_restaurants')
            .select('id,name,district,latitude,longitude,is_open,delivery_available,status')
            .eq('status', 'active')
            .not('latitude', 'is', null)
            .not('longitude', 'is', null)
            .limit(MAX_RESULTS);
          if (filters.openNow) q = q.eq('is_open', true);
          if (filters.deliveryOnly) q = q.eq('delivery_available', true);
          const { data, error: e } = await q;
          if (e) throw e;
          for (const r of data ?? []) {
            if (r.latitude == null || r.longitude == null) continue;
            out.push({
              id: r.id, name: r.name, slug: null, district: r.district ?? null,
              latitude: r.latitude as number, longitude: r.longitude as number,
              kind: 'restaurant',
              deliveryAvailable: !!r.delivery_available,
              isOpen: r.is_open as boolean,
            });
          }
        } catch (e: any) {
          rErr = e?.message ?? 'repas discovery failed';
        }
      }

      if (filters.stores !== false || filters.marche) {
        try {
          let q = supabase
            .from('merchant_stores')
            .select('id,name,slug,district,latitude,longitude,delivery_available,category,status')
            .eq('status', 'active')
            .not('latitude', 'is', null)
            .not('longitude', 'is', null)
            .limit(MAX_RESULTS);
          if (filters.deliveryOnly) q = q.eq('delivery_available', true);
          if (filters.marche) q = q.eq('category', 'marche');
          const { data, error: e } = await q;
          if (e) throw e;
          for (const s of data ?? []) {
            if (s.latitude == null || s.longitude == null) continue;
            out.push({
              id: s.id, name: s.name, slug: (s as any).slug ?? null, district: s.district ?? null,
              latitude: s.latitude as number, longitude: s.longitude as number,
              kind: 'store',
              deliveryAvailable: !!s.delivery_available,
              isOpen: null,
            });
          }
        } catch (e: any) {
          sErr = e?.message ?? 'marche discovery failed';
        }
      }

      if (cancelled) return;
      setRestaurantError(rErr);
      setStoreError(sErr);
      setVendors(out.slice(0, MAX_RESULTS));
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [enabled, filters.restaurants, filters.stores, filters.marche, filters.openNow, filters.deliveryOnly]);

  return {
    vendors,
    loading,
    restaurantError,
    storeError,
    /** Legacy aggregate: non-null only when every attempted vertical failed. */
    error:
      (filters.restaurants !== false && filters.stores === false && restaurantError) ||
      (filters.stores !== false && filters.restaurants === false && storeError) ||
      (restaurantError && storeError ? `${restaurantError}; ${storeError}` : null),
  };
}
