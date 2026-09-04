import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor, act } from "@testing-library/react";
import React from "react";

/**
 * Ride booking — "Choisir la destination sur la carte".
 *
 * Root cause covered here: the CTA did set pick mode, but (a) the inline map
 * slot collapsed to a few dozen pixels on a phone so there was nothing to tap,
 * and (b) the map tap awaited reverse-geocoding before committing anything, so
 * a slow/failing provider left the field empty and pick mode stuck.
 */

vi.mock("react-map-gl", () => {
  const Map = React.forwardRef(function Map(props: any, ref: any) {
    React.useImperativeHandle(ref, () => ({ flyTo: vi.fn(), fitBounds: vi.fn() }));
    return (
      <div data-testid="mapbox" data-interactive={String(props.interactive)}>
        <button
          data-testid="map-canvas"
          onClick={() => props.onClick?.({ lngLat: { lng: -13.61, lat: 9.55 } })}
        />
        <button
          data-testid="map-canvas-2"
          onClick={() => props.onClick?.({ lngLat: { lng: -13.42, lat: 9.71 } })}
        />
        {props.children}
      </div>
    );
  });
  const Marker = ({ children, longitude, latitude }: any) => (
    <div data-testid="marker" data-lng={longitude} data-lat={latitude}>
      {children}
    </div>
  );
  const Source = ({ children }: any) => <div>{children}</div>;
  const Layer = () => null;
  return { default: Map, Map, Marker, Source, Layer };
});
vi.mock("mapbox-gl/dist/mapbox-gl.css", () => ({}));
vi.mock("@/hooks/useLowDataMode", () => ({ useLowDataMode: () => ({ low: false }) }));

const reverseGeocode = vi.fn();
vi.mock("@/lib/maps", async (orig) => {
  const actual = (await orig()) as Record<string, unknown>;
  return {
    ...actual,
    useMapConfig: () => ({
      config: {
        mapboxToken: "pk.test",
        styleUrl: "mapbox://styles/mapbox/light-v11",
        defaultCenter: { lat: 9.6412, lng: -13.5784 },
        defaultZoom: 12,
        flags: { heatmap: false, surge: false, clustering: true },
        provider: "google",
      },
      error: null,
      loading: false,
      retry: vi.fn(),
    }),
    reverseGeocode: (...a: unknown[]) => reverseGeocode(...a),
    searchPlaces: vi.fn(async () => ({ results: [], provider: "none" })),
    RoutingService: { route: vi.fn(async () => null) },
  };
});

vi.mock("@/components/map/NearbyAvailableDrivers", () => ({
  NearbyAvailableDrivers: () => null,
}));
vi.mock("@/components/map/DriverMarker", () => ({ DriverMarker: () => null }));
vi.mock("@/lib/locations/searchPlaces", () => ({
  searchConakryPlaces: vi.fn(() => []),
  categoryLabel: () => "",
  confidenceLabel: () => null,
}));
vi.mock("@/lib/locations/locationSearchTelemetry", () => ({
  logLocationSearchEvent: vi.fn(),
}));
vi.mock("@/lib/location/useLiveUserLocation", () => ({
  useLiveUserLocation: () => ({ coords: null, isRealLocation: false, refresh: vi.fn() }),
  CONAKRY_FALLBACK: { lat: 9.6412, lng: -13.5784 },
}));
vi.mock("@/contexts/AuthContext", () => ({ useAuth: () => ({ isLoggedIn: false, user: null }) }));
const navigate = vi.fn();
vi.mock("react-router-dom", () => ({ useNavigate: () => navigate }));
const rpc = vi.fn(async () => ({ data: null, error: { message: "auth" } }));
vi.mock("@/integrations/supabase/client", () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...(a as [])) } }));

import { RideBooking } from "@/components/ride/RideBooking";

const onBook = vi.fn();
const onClose = vi.fn();

function renderBooking(type: "moto" | "toktok" | "auto" = "moto", initialDestination?: string) {
  return render(
    <RideBooking type={type} onClose={onClose} onBook={onBook} initialDestination={initialDestination} />,
  );
}

async function openPickMode() {
  fireEvent.focus(screen.getByPlaceholderText("Destination"));
  const cta = await screen.findByTestId("ride-pick-on-map");
  fireEvent.click(cta);
}

beforeEach(() => {
  vi.clearAllMocks();
  reverseGeocode.mockResolvedValue({ label: "Rond-point Bambeto", secondary_label: null });
});

describe("Ride booking — choose destination on map", () => {
  it("A. the CTA fires the map-pick transition", async () => {
    renderBooking();
    await openPickMode();
    expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("destination");
    expect(screen.getByTestId("ride-map-pick-banner")).toHaveTextContent(/choisir la destination/i);
  });

  it("B. the destination search sheet closes", async () => {
    renderBooking();
    await openPickMode();
    expect(screen.queryByTestId("ride-pick-on-map")).toBeNull();
  });

  it("C. the ride map is full-screen and interactive in pick mode", async () => {
    renderBooking();
    await openPickMode();
    const surface = screen.getByTestId("ride-map-surface");
    expect(surface.style.position).toBe("fixed");
    expect(surface.className).not.toContain("min-h-0");
    expect(screen.getByTestId("mapbox").getAttribute("data-interactive")).toBe("true");
  });

  it("D+E. a map tap commits the coordinate and the geocoded label", async () => {
    renderBooking();
    await openPickMode();
    await act(async () => {
      fireEvent.click(screen.getByTestId("map-canvas"));
    });
    expect(reverseGeocode).toHaveBeenCalledWith(9.55, -13.61);
    const marker = screen.getAllByTestId("marker").at(-1)!;
    expect(marker.getAttribute("data-lat")).toBe("9.55");
    expect(marker.getAttribute("data-lng")).toBe("-13.61");
    await waitFor(() =>
      expect((screen.getByPlaceholderText("Destination") as HTMLInputElement).value).toBe(
        "Rond-point Bambeto",
      ),
    );
  });

  it("F. reverse-geocode failure keeps the coordinate with an honest label", async () => {
    reverseGeocode.mockRejectedValue(new Error("offline"));
    renderBooking();
    await openPickMode();
    await act(async () => {
      fireEvent.click(screen.getByTestId("map-canvas"));
    });
    const marker = screen.getAllByTestId("marker").at(-1)!;
    expect(marker.getAttribute("data-lat")).toBe("9.55");
    await waitFor(() =>
      expect((screen.getByPlaceholderText("Destination") as HTMLInputElement).value).toBe(
        "Point sur la carte (9.55000, -13.61000)",
      ),
    );
  });

  it("F2. a pending reverse-geocode never blocks the commit", async () => {
    reverseGeocode.mockReturnValue(new Promise(() => {}));
    renderBooking();
    await openPickMode();
    fireEvent.click(screen.getByTestId("map-canvas"));
    expect((screen.getByPlaceholderText("Destination") as HTMLInputElement).value).toContain(
      "Point sur la carte",
    );
    expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("off");
  });

  it("G. pick mode exits after the commit", async () => {
    renderBooking();
    await openPickMode();
    await act(async () => {
      fireEvent.click(screen.getByTestId("map-canvas"));
    });
    expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("off");
    expect(screen.queryByTestId("ride-map-pick-banner")).toBeNull();
  });

  it("H. cancel exits pick mode without overwriting the destination", async () => {
    renderBooking("moto", "Kaloum");
    await openPickMode();
    fireEvent.click(screen.getByText("Annuler"));
    expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("off");
    expect((screen.getByPlaceholderText("Destination") as HTMLInputElement).value).toBe("Kaloum");
    expect(reverseGeocode).not.toHaveBeenCalled();
  });

  it("I. repeated pick attempts work with no stale state", async () => {
    renderBooking();
    await openPickMode();
    await act(async () => {
      fireEvent.click(screen.getByTestId("map-canvas"));
    });
    await openPickMode();
    expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("destination");
    await act(async () => {
      fireEvent.click(screen.getByTestId("map-canvas-2"));
    });
    const marker = screen.getAllByTestId("marker").at(-1)!;
    expect(marker.getAttribute("data-lat")).toBe("9.71");
    expect(marker.getAttribute("data-lng")).toBe("-13.42");
    expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("off");
  });

  it("J. selecting a point never books a ride", async () => {
    renderBooking();
    await openPickMode();
    await act(async () => {
      fireEvent.click(screen.getByTestId("map-canvas"));
    });
    expect(onBook).not.toHaveBeenCalled();
  });

  it("K. the same picker works for Bonbonna and Taxi", async () => {
    for (const type of ["toktok", "auto"] as const) {
      const { unmount } = renderBooking(type);
      await openPickMode();
      await act(async () => {
        fireEvent.click(screen.getByTestId("map-canvas"));
      });
      expect(screen.getByTestId("ride-map-surface").getAttribute("data-pick-mode")).toBe("off");
      expect(onBook).not.toHaveBeenCalled();
      unmount();
    }
  });
});
