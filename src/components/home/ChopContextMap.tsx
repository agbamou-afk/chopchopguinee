import { Marker } from "react-map-gl";
import { ChopMap, MapMarker, NearbyAvailableDrivers, VendorDiscoveryLayer } from "@/components/map";
import type { DiscoveryVendor } from "@/lib/locations/useVendorDiscovery";

/**
 * Explicit map context. There is only ONE map stack (`ChopMap`); the mode
 * decides which semantic layers are mounted.
 *
 *  - `directory` (Home default): local commerce only — restaurants + boutiques.
 *    No driver markers, no ride intent anywhere in the surface.
 *  - `ride`: unchanged legacy behaviour for Moto / Bonbonna / Taxi flows.
 */
export type ChopMapMode = "directory" | "ride";

export interface ChopContextMapProps {
  lng: number;
  lat: number;
  /**
   * True only when (lng, lat) reflects the user's real device location.
   * When false, the map is centered on a fallback (e.g. Conakry) and we
   * MUST NOT render a "Vous" pin pretending the user is there.
   */
  userPresent?: boolean;
  mode?: ChopMapMode;
  interactive?: boolean;
  zoom?: number;
  /** Directory mode only — which verticals may be pinned (exposure law). */
  showRestaurants?: boolean;
  showStores?: boolean;
  onVendorSelect?: (vendor: DiscoveryVendor) => void;
  className?: string;
}

export default function ChopContextMap({
  lng,
  lat,
  userPresent = false,
  mode = "ride",
  interactive = false,
  zoom = 13,
  showRestaurants = true,
  showStores = true,
  onVendorSelect,
  className,
}: ChopContextMapProps) {
  const directory = mode === "directory";
  return (
    <ChopMap
      className={className ?? "absolute inset-0 w-full h-full"}
      interactive={interactive}
      initialView={{ longitude: lng, latitude: lat, zoom }}
    >
      {/* Ride semantics are mounted ONLY in explicit ride context. */}
      {!directory && (
        <NearbyAvailableDrivers
          lat={userPresent ? lat : null}
          lng={userPresent ? lng : null}
          vehicleType="moto"
        />
      )}
      {/* Customer-only: nearby public restaurants & boutiques (with coords). */}
      <VendorDiscoveryLayer
        enabled={directory ? showRestaurants || showStores : true}
        filters={
          directory
            ? { restaurants: showRestaurants, stores: showStores }
            : { restaurants: true, stores: true }
        }
        onSelect={directory ? onVendorSelect : undefined}
      />
      {userPresent && (
        <Marker longitude={lng} latitude={lat} anchor="center">
          <MapMarker variant="pickup" pulse size={28} label="Vous" />
        </Marker>
      )}
    </ChopMap>
  );
}
