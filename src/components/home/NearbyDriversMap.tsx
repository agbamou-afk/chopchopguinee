import { Marker } from "react-map-gl";
import { ChopMap, DriverCluster, MapMarker, VendorDiscoveryLayer } from "@/components/map";

interface Props { lng: number; lat: number; }

export default function NearbyDriversMap({ lng, lat }: Props) {
  return (
    <ChopMap
      className="absolute inset-0 w-full h-full"
      interactive={false}
      initialView={{ longitude: lng, latitude: lat, zoom: 13 }}
    >
      <DriverCluster variant="moto" />
      {/* Customer-only: nearby public restaurants & boutiques (with coords). */}
      <VendorDiscoveryLayer enabled filters={{ restaurants: true, stores: true }} />
      <Marker longitude={lng} latitude={lat} anchor="center">
        <MapMarker variant="pickup" pulse size={28} label="Vous" />
      </Marker>
    </ChopMap>
  );
}