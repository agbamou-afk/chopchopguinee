import { Marker } from "react-map-gl";
import { useNearbyAvailableDrivers } from "@/hooks/useNearbyAvailableDrivers";
import { MapMarker } from "./MapMarker";

interface Props {
  lat: number | null;
  lng: number | null;
  vehicleType?: "moto" | "toktok" | null;
  radiusM?: number;
  enabled?: boolean;
}

/**
 * Renders nearby APPROVED + ONLINE drivers on the map using the privacy-safe
 * RPC (`get_nearby_available_drivers`). Coordinates are rounded to ~110m and
 * the driver_ref is an opaque, per-hour hash — never the real user_id.
 */
export function NearbyAvailableDrivers({
  lat, lng, vehicleType = null, radiusM = 3000, enabled = true,
}: Props) {
  const { drivers } = useNearbyAvailableDrivers({
    lat, lng, vehicleType, radiusM, enabled,
  });
  return (
    <>
      {drivers.map((d) => (
        <Marker key={d.driver_ref} longitude={d.approx_lng} latitude={d.approx_lat} anchor="center">
          <MapMarker
            variant={vehicleType === "toktok" ? "toktok" : "moto"}
            state="online"
            rotation={d.heading ?? 0}
            size={28}
            label="Chauffeur"
          />
        </Marker>
      ))}
    </>
  );
}