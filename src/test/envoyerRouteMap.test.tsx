import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import React from "react";

// ---- Map stack stubs -------------------------------------------------------
const fitBounds = vi.fn();
const flyTo = vi.fn();

vi.mock("react-map-gl", () => {
  const Map = React.forwardRef(function Map(props: any, ref: any) {
    React.useImperativeHandle(ref, () => ({ flyTo, fitBounds }));
    return (
      <div data-testid="mapbox">
        <button
          data-testid="map-canvas"
          onClick={() => props.onClick?.({ lngLat: { lng: -13.6, lat: 9.55 } })}
        />
        {props.children}
      </div>
    );
  });
  const Marker = ({ children, longitude, latitude, onDragEnd }: any) => (
    <div data-testid="marker" data-lng={longitude} data-lat={latitude}>
      <button
        data-testid="marker-drag"
        onClick={() => onDragEnd?.({ lngLat: { lng: -13.7, lat: 9.7 } })}
      />
      {children}
    </div>
  );
  const Source = ({ children }: any) => <div data-testid="route-line">{children}</div>;
  const Layer = () => null;
  return { default: Map, Map, Marker, Source, Layer };
});

vi.mock("mapbox-gl/dist/mapbox-gl.css", () => ({}));

let mapConfigError: Error | null = null;
vi.mock("@/lib/maps", async (orig) => {
  const actual = (await orig()) as Record<string, unknown>;
  return {
    ...actual,
    useMapConfig: () => ({
      config: mapConfigError
        ? null
        : {
            mapboxToken: "pk.test",
            styleUrl: "mapbox://styles/mapbox/light-v11",
            defaultCenter: { lat: 9.6412, lng: -13.5784 },
            defaultZoom: 12,
            flags: { heatmap: false, surge: false, clustering: true },
            provider: "google",
          },
      error: mapConfigError,
      loading: false,
    }),
  };
});

vi.mock("@/hooks/useLowDataMode", () => ({ useLowDataMode: () => ({ low: false }) }));

const reverseGeocode = vi.fn();
vi.mock("@/lib/maps/placeSearch", () => ({
  reverseGeocode: (...a: unknown[]) => reverseGeocode(...a),
  searchPlaces: vi.fn(async () => ({ results: [], provider: "none" })),
}));

import { RouteMapPicker } from "@/components/envoyer/RouteMapPicker";
import {
  MANUAL_POINT_LABEL,
  canAdvanceItinerary,
  isSamePoint,
  routeFitBbox,
} from "@/lib/envoyer/routePoints";

const PICKUP = { lat: 9.64, lng: -13.58, label: "Sangoyah Marché" };
const DEST = { lat: 9.53, lng: -13.66, label: "Madina" };

beforeEach(() => {
  vi.clearAllMocks();
  mapConfigError = null;
  reverseGeocode.mockResolvedValue({ label: "Quartier Madina" });
});

describe("Envoyer route map picker", () => {
  it("renders both endpoints as markers and fits them", () => {
    render(
      <RouteMapPicker pickup={PICKUP} destination={DEST} active="pickup" onChange={vi.fn()} />,
    );
    const markers = screen.getAllByTestId("marker");
    expect(markers).toHaveLength(2);
    expect(fitBounds).toHaveBeenCalled();
    expect(screen.getByTestId("route-line")).toBeInTheDocument();
  });

  it("map tap moves ONLY the active pickup point", async () => {
    const onChange = vi.fn();
    render(
      <RouteMapPicker pickup={PICKUP} destination={DEST} active="pickup" onChange={onChange} />,
    );
    fireEvent.click(screen.getByTestId("map-canvas"));
    expect(onChange).toHaveBeenCalledWith("pickup", {
      lat: 9.55,
      lng: -13.6,
      label: MANUAL_POINT_LABEL,
    });
    expect(onChange.mock.calls.every((c) => c[0] === "pickup")).toBe(true);
  });

  it("map tap moves ONLY the active destination point", () => {
    const onChange = vi.fn();
    render(
      <RouteMapPicker
        pickup={PICKUP}
        destination={DEST}
        active="destination"
        onChange={onChange}
      />,
    );
    fireEvent.click(screen.getByTestId("map-canvas"));
    expect(onChange).toHaveBeenCalledWith("destination", expect.objectContaining({ lat: 9.55 }));
    expect(onChange.mock.calls.every((c) => c[0] === "destination")).toBe(true);
  });

  it("dragging a marker updates only that endpoint", () => {
    const onChange = vi.fn();
    render(
      <RouteMapPicker pickup={PICKUP} destination={DEST} active="pickup" onChange={onChange} />,
    );
    // second marker = destination
    fireEvent.click(screen.getAllByTestId("marker-drag")[1]);
    expect(onChange).toHaveBeenCalledWith("destination", {
      lat: 9.7,
      lng: -13.7,
      label: MANUAL_POINT_LABEL,
    });
    expect(onChange.mock.calls.every((c) => c[0] === "destination")).toBe(true);
  });

  it("enriches a manual point with the reverse-geocoded label", async () => {
    const onChange = vi.fn();
    render(<RouteMapPicker pickup={null} destination={null} active="pickup" onChange={onChange} />);
    fireEvent.click(screen.getByTestId("map-canvas"));
    await waitFor(() =>
      expect(onChange).toHaveBeenCalledWith("pickup", {
        lat: 9.55,
        lng: -13.6,
        label: "Quartier Madina",
      }),
    );
  });

  it("keeps coordinates with a neutral label when reverse geocoding fails", async () => {
    reverseGeocode.mockResolvedValue(null);
    const onChange = vi.fn();
    render(<RouteMapPicker pickup={null} destination={null} active="pickup" onChange={onChange} />);
    fireEvent.click(screen.getByTestId("map-canvas"));
    await waitFor(() => expect(reverseGeocode).toHaveBeenCalled());
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith("pickup", {
      lat: 9.55,
      lng: -13.6,
      label: MANUAL_POINT_LABEL,
    });
  });

  it("falls back to a usable French notice when the map fails", () => {
    mapConfigError = new Error("unauthenticated");
    render(
      <RouteMapPicker pickup={PICKUP} destination={DEST} active="pickup" onChange={vi.fn()} />,
    );
    expect(screen.getByTestId("envoyer-map-fallback")).toBeInTheDocument();
    expect(screen.queryByTestId("mapbox")).not.toBeInTheDocument();
  });

  it("keeps a non-zero map container height on mobile", () => {
    render(
      <RouteMapPicker pickup={PICKUP} destination={DEST} active="pickup" onChange={vi.fn()} />,
    );
    const box = screen.getByTestId("envoyer-route-map");
    expect(box.className).toMatch(/min-h-\[240px\]/);
    expect(box.className).toMatch(/h-\[42vh\]/);
  });
});

describe("Envoyer itinerary coordinate law", () => {
  it("blocks Continue when both points are effectively the same spot", () => {
    const near = { lat: PICKUP.lat + 0.00005, lng: PICKUP.lng };
    expect(isSamePoint(PICKUP, near)).toBe(true);
    expect(canAdvanceItinerary(PICKUP, near)).toBe(false);
    expect(canAdvanceItinerary(PICKUP, DEST)).toBe(true);
    expect(canAdvanceItinerary(PICKUP, null)).toBe(false);
  });

  it("computes fit bounds only when both endpoints exist", () => {
    expect(routeFitBbox(PICKUP, null)).toBeNull();
    expect(routeFitBbox(PICKUP, DEST)).toEqual([-13.66, 9.53, -13.58, 9.64]);
  });
});
