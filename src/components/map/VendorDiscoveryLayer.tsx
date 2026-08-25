import { useMemo, useState } from 'react';
import { Marker, Popup } from 'react-map-gl';
import { ChopPin } from './ChopPin';
import { useVendorDiscovery, type VendorDiscoveryFilters, type DiscoveryVendor } from '@/lib/locations/useVendorDiscovery';

interface Props {
  /** Only show in customer-facing surfaces. Driver-mode callers must pass false. */
  enabled?: boolean;
  filters?: VendorDiscoveryFilters;
  /**
   * Click-through into the existing public commerce surfaces
   * (`/marche/boutique/:slug` for stores, Repas detail for restaurants).
   * When omitted the layer keeps the read-only popup behaviour.
   */
  onSelect?: (vendor: DiscoveryVendor) => void;
}

/**
 * Customer-only map layer showing nearby public commercial points
 * (restaurants + boutiques) that have explicit public coordinates.
 *
 * Privacy guarantees (see `useVendorDiscovery`):
 *   - Customers, couriers, private sellers never appear here.
 *   - Vendors without lat/lng never appear here.
 *   - Capped at 50 pins.
 *
 * TODO(discovery): add hub/agent/Chop point pins once those tables ship.
 */
export function VendorDiscoveryLayer({ enabled = true, filters = {}, onSelect }: Props) {
  const { vendors } = useVendorDiscovery(filters, { enabled });
  const [openId, setOpenId] = useState<string | null>(null);
  const open = useMemo(() => vendors.find((v) => v.id === openId) ?? null, [vendors, openId]);
  if (!enabled || vendors.length === 0) return null;

  return (
    <>
      {vendors.map((v) => (
        <Marker
          key={`${v.kind}-${v.id}`}
          longitude={v.longitude}
          latitude={v.latitude}
          anchor="bottom"
          onClick={(e) => { e.originalEvent.stopPropagation(); setOpenId(v.id); }}
        >
          <ChopPin
            kind={{ family: 'actor', key: v.kind === 'restaurant' ? 'restaurant' : 'boutique' }}
            label={v.name}
          />
        </Marker>
      ))}
      {open && (
        <Popup
          longitude={open.longitude}
          latitude={open.latitude}
          anchor="top"
          closeOnClick={false}
          onClose={() => setOpenId(null)}
          className="!p-0"
        >
          <div className="px-1 py-1 min-w-[160px]">
            <p className="text-sm font-semibold leading-tight">{open.name}</p>
            <p className="text-[11px] text-muted-foreground">
              {[open.district, open.kind === 'restaurant' ? 'Restaurant' : 'Boutique'].filter(Boolean).join(' · ')}
            </p>
            {open.deliveryAvailable && (
              <p className="text-[10px] text-primary mt-0.5">Livraison disponible</p>
            )}
            {onSelect && (
              <button
                type="button"
                data-testid={`vendor-open-${open.kind}`}
                onClick={() => onSelect(open)}
                className="mt-1.5 text-[11px] font-semibold text-primary"
              >
                {open.kind === 'restaurant' ? 'Voir le menu' : 'Voir la boutique'}
              </button>
            )}
          </div>

        </Popup>
      )}
    </>
  );
}