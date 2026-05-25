import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export type VendorKind = 'restaurant' | 'store';

export interface DiscoveryVendor {
  id: string;
  name: string;
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
 * Intended to run only when the customer discovery map is mounted.
 */
const MAX_RESULTS = 50;

export function useVendorDiscovery(
  filters: VendorDiscoveryFilters,
  opts: { enabled?: boolean } = {},
) {
  const { enabled = true } = opts;
  const [vendors, setVendors] = useState<DiscoveryVendor[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled) { setVendors([]); return; }
    let cancelled = false;
    setLoading(true); setError(null);
    (async () => {
      const out: DiscoveryVendor[] = [];
      try {
        if (filters.restaurants !== false) {
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
              id: r.id, name: r.name, district: r.district ?? null,
              latitude: r.latitude as number, longitude: r.longitude as number,
              kind: 'restaurant',
              deliveryAvailable: !!r.delivery_available,
              isOpen: r.is_open as boolean,
            });
          }
        }
        if (filters.stores !== false || filters.marche) {
          let q = supabase
            .from('merchant_stores')
            .select('id,name,district,latitude,longitude,delivery_available,category,status')
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
              id: s.id, name: s.name, district: s.district ?? null,
              latitude: s.latitude as number, longitude: s.longitude as number,
              kind: 'store',
              deliveryAvailable: !!s.delivery_available,
              isOpen: null,
            });
          }
        }
        if (!cancelled) setVendors(out.slice(0, MAX_RESULTS));
      } catch (e: any) {
        if (!cancelled) setError(e?.message ?? 'discovery failed');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [enabled, filters.restaurants, filters.stores, filters.marche, filters.openNow, filters.deliveryOnly]);

  return { vendors, loading, error };
}