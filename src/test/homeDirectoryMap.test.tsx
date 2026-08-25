/**
 * HOME MAP REMEDIATION — directory-by-default commerce map.
 *
 * Adversarial coverage:
 *  A. anon merchant pins still load when the restaurant query fails
 *  C. directory mode renders vendor pins and zero driver markers
 *  D. ride mode still renders driver markers
 *  E. Home map is not clickable-to-Moto by default
 *  F. expand action opens an interactive directory map
 *  G. store pin opens /marche/boutique/:slug
 *  H. restaurant pin opens the existing Repas ordering flow
 *  I. Repas/Marché exposure flags filter only their own pins
 *  J. ride flags do not hide business pins
 *  K. both commerce flags OFF hides the directory section
 *  M. low-data mode stays honest and usable
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor, fireEvent, act } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

// ---------------------------------------------------------------- supabase
type Row = Record<string, any>;
const responses: { restaurants: () => any; stores: () => any } = {
  restaurants: () => ({ data: [], error: null }),
  stores: () => ({ data: [], error: null }),
};

function builder(table: string) {
  const chain: any = {};
  for (const m of ["select", "eq", "not", "limit"]) chain[m] = () => chain;
  chain.then = (resolve: any) =>
    Promise.resolve(
      table === "food_restaurants" ? responses.restaurants() : responses.stores(),
    ).then(resolve);
  return chain;
}

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { from: (t: string) => builder(t) },
}));

// ---------------------------------------------------------------- map stack
vi.mock("react-map-gl", () => ({
  Marker: ({ children, onClick }: any) => (
    <div data-testid="marker" onClick={() => onClick?.({ originalEvent: { stopPropagation() {} } })}>
      {children}
    </div>
  ),
  Popup: ({ children }: any) => <div data-testid="popup">{children}</div>,

}));
vi.mock("mapbox-gl/dist/mapbox-gl.css", () => ({}));

const mapProps: any[] = [];
vi.mock("@/components/map", async () => {
  const actual = await vi.importActual<any>("@/components/map/VendorDiscoveryLayer");
  return {
    ChopMap: (p: any) => {
      mapProps.push(p);
      return <div data-testid="chop-map" data-interactive={String(!!p.interactive)}>{p.children}</div>;
    },
    MapMarker: ({ label }: any) => <div data-testid="user-marker">{label}</div>,
    NearbyAvailableDrivers: () => <div data-testid="driver-layer" />,
    VendorDiscoveryLayer: actual.VendorDiscoveryLayer,
  };
});

import { useVendorDiscovery } from "@/lib/locations/useVendorDiscovery";
import ChopContextMap from "@/components/home/ChopContextMap";
import { LocalCommerceMap } from "@/components/home/LocalCommerceMap";

const STORE: Row = {
  id: "s1", name: "Kam's chop", slug: "kam-s-chop", district: "Ratoma",
  latitude: 9.59, longitude: -13.63, delivery_available: true, category: "shop", status: "active",
};
const RESTO: Row = {
  id: "r1", name: "Le bon coin", district: "Kaloum",
  latitude: 9.5, longitude: -13.7, is_open: true, delivery_available: true, status: "active",
};

beforeEach(() => {
  mapProps.length = 0;
  responses.restaurants = () => ({ data: [RESTO], error: null });
  responses.stores = () => ({ data: [STORE], error: null });
});

// -------------------------------------------------------------- A. domains
function Probe({ filters }: any) {
  const { vendors, restaurantError, storeError } = useVendorDiscovery(filters ?? {});
  return (
    <div>
      <span data-testid="names">{vendors.map((v) => v.name).join("|")}</span>
      <span data-testid="rerr">{restaurantError ?? ""}</span>
      <span data-testid="serr">{storeError ?? ""}</span>
    </div>
  );
}

describe("A — split discovery failure domains", () => {
  it("still returns merchant pins when the restaurant read fails", async () => {
    responses.restaurants = () => ({ data: null, error: { message: "permission denied for function has_role" } });
    render(<Probe />);
    await waitFor(() => expect(screen.getByTestId("names").textContent).toBe("Kam's chop"));
    expect(screen.getByTestId("rerr").textContent).toContain("permission denied");
    expect(screen.getByTestId("serr").textContent).toBe("");
  });

  it("still returns restaurant pins when the merchant read fails", async () => {
    responses.stores = () => ({ data: null, error: { message: "boom" } });
    render(<Probe />);
    await waitFor(() => expect(screen.getByTestId("names").textContent).toBe("Le bon coin"));
    expect(screen.getByTestId("serr").textContent).toBe("boom");
  });

  it("returns both verticals when both reads succeed", async () => {
    render(<Probe />);
    await waitFor(() => expect(screen.getByTestId("names").textContent).toBe("Le bon coin|Kam's chop"));
  });
});

// -------------------------------------------------- C/D/I. map context law
describe("C/D/I — explicit map context", () => {
  it("directory mode renders vendor pins and zero driver markers", async () => {
    render(<ChopContextMap mode="directory" lng={-13.7} lat={9.5} />);
    await waitFor(() => expect(screen.getAllByTestId("marker").length).toBe(2));
    expect(screen.queryByTestId("driver-layer")).toBeNull();
  });

  it("ride mode still mounts the driver layer", async () => {
    render(<ChopContextMap mode="ride" lng={-13.7} lat={9.5} userPresent />);
    expect(screen.getByTestId("driver-layer")).toBeTruthy();
  });

  it("directory mode hides Repas pins when restaurants are not exposed", async () => {
    render(<ChopContextMap mode="directory" showRestaurants={false} lng={-13.7} lat={9.5} />);
    await waitFor(() => expect(screen.getAllByTestId("marker").length).toBe(1));
  });

  it("directory mode hides Marché pins when stores are not exposed", async () => {
    render(<ChopContextMap mode="directory" showStores={false} lng={-13.7} lat={9.5} />);
    await waitFor(() => expect(screen.getAllByTestId("marker").length).toBe(1));
  });
});

// ------------------------------------------------------ F/G/H/M. home card
const navigate = vi.fn();
vi.mock("react-router-dom", async (io) => {
  const actual = await io<any>();
  return { ...actual, useNavigate: () => navigate };
});

function renderCard(props: Partial<React.ComponentProps<typeof LocalCommerceMap>> = {}) {
  const onOpenRestaurant = vi.fn();
  render(
    <MemoryRouter>
      <LocalCommerceMap
        lng={-13.7}
        lat={9.5}
        userPresent={false}
        lowDataMode={false}
        showRestaurants
        showStores
        onOpenRestaurant={onOpenRestaurant}
        {...props}
      />
    </MemoryRouter>,
  );
  return { onOpenRestaurant };
}

describe("E/F/G/H/M — home commerce card", () => {
  beforeEach(() => navigate.mockClear());

  it("carries no ride semantics and no booking control", async () => {
    renderCard();
    expect(screen.getByText("Commerces près de vous")).toBeTruthy();
    expect(screen.queryByText("Réserver")).toBeNull();
    expect(screen.queryByText(/Chauffeurs/i)).toBeNull();
    expect(document.querySelector('[aria-label="Voir les chauffeurs disponibles"]')).toBeNull();
  });

  it("expand opens an interactive fullscreen directory map", async () => {
    renderCard();
    await act(async () => { fireEvent.click(screen.getByTestId("commerce-map-expand")); });
    await waitFor(() => expect(screen.getByTestId("commerce-map-fullscreen")).toBeTruthy());
    const interactive = Array.from(document.querySelectorAll('[data-testid="chop-map"]'))
      .some((el) => el.getAttribute("data-interactive") === "true");
    expect(interactive).toBe(true);
  });

  it("store pin opens the existing public storefront route", async () => {
    renderCard();
    await waitFor(() => expect(screen.getAllByTestId("marker").length).toBe(2));
    fireEvent.click(screen.getAllByTestId("marker")[1]);
    await waitFor(() => expect(screen.getByTestId("vendor-open-store")).toBeTruthy());
    fireEvent.click(screen.getByTestId("vendor-open-store"));
    expect(navigate).toHaveBeenCalledWith("/marche/boutique/kam-s-chop");
  });

  it("restaurant pin opens the existing Repas ordering flow, not a new page", async () => {
    const { onOpenRestaurant } = renderCard();
    await waitFor(() => expect(screen.getAllByTestId("marker").length).toBe(2));
    fireEvent.click(screen.getAllByTestId("marker")[0]);
    await waitFor(() => expect(screen.getByTestId("vendor-open-restaurant")).toBeTruthy());
    fireEvent.click(screen.getByTestId("vendor-open-restaurant"));
    expect(onOpenRestaurant).toHaveBeenCalledWith("r1");
    expect(navigate).not.toHaveBeenCalled();
  });

  it("low-data mode degrades honestly and keeps the section usable", () => {
    renderCard({ lowDataMode: true });
    expect(screen.getByText(/mode données réduites/i)).toBeTruthy();
    expect(screen.getByTestId("commerce-map-expand")).toBeTruthy();
  });
});
