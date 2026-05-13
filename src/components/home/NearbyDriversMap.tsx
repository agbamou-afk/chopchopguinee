import { Marker } from "react-map-gl";
import { ChopMap, DriverCluster, MapMarker } from "@/components/map";

interface Props { lng: number; lat: number; }

export default function NearbyDriversMap({ lng, lat }: Props) {
  return (
    <ChopMap
      className="absolute inset-0 w-full h-full"
      interactive={false}
      initialView={{ longitude: lng, latitude: lat, zoom: 13 }}
    >
      <DriverCluster variant="moto" />
      <Marker longitude={lng} latitude={lat} anchor="center">
        <MapMarker variant="pickup" pulse size={28} label="Vous" />
      </Marker>
    </ChopMap>
  );
}