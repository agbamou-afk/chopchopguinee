import { Marker } from "react-map-gl";
import { ChopMap, MapMarker, NearbyAvailableDrivers, VendorDiscoveryLayer } from "@/components/map";

interface Props {
  lng: number;
  lat: number;
  /**
   * True only when (lng, lat) reflects the user's real device location.
   * When false, the map is centered on a fallback (e.g. Conakry) and we
   * MUST NOT render a "Vous" pin pretending the user is there.
   */
  userPresent?: boolean;
}

export default function NearbyDriversMap({ lng, lat, userPresent = false }: Props) {
  return (
    <ChopMap
      className="absolute inset-0 w-full h-full"
      interactive={false}
      initialView={{ longitude: lng, latitude: lat, zoom: 13 }}
    >
      {/* Privacy-safe — RPC returns only approved + online drivers, rounded coords. */}
      <NearbyAvailableDrivers lat={userPresent ? lat : null} lng={userPresent ? lng : null} vehicleType="moto" />
      {/* Customer-only: nearby public restaurants & boutiques (with coords). */}
      <VendorDiscoveryLayer enabled filters={{ restaurants: true, stores: true }} />
      {userPresent && (
        <Marker longitude={lng} latitude={lat} anchor="center">
          <MapMarker variant="pickup" pulse size={28} label="Vous" />
        </Marker>
      )}
    </ChopMap>
  );
}