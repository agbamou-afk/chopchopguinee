import ChopContextMap from "./ChopContextMap";

interface Props {
  lng: number;
  lat: number;
  userPresent?: boolean;
}

/**
 * Ride-context map (Moto / Bonbonna / Taxi surfaces). Kept as a thin wrapper
 * over the single map stack so ride semantics stay exactly as before.
 */
export default function NearbyDriversMap({ lng, lat, userPresent = false }: Props) {
  return <ChopContextMap mode="ride" lng={lng} lat={lat} userPresent={userPresent} />;
}
