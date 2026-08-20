import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

const rpcMock = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...a) },
}));

import { ObservedPriceBadge } from "@/components/marche/ObservedPriceBadge";
import {
  PRICE_FRESHNESS_VALUES,
  clearObservedPriceCache,
  fetchObservedPrices,
  freshnessLabel,
  isSpecificZone,
  pickVariantCohort,
  zoneLabel,
  type PriceCohort,
} from "@/lib/marche/priceIntelligence";

const baseCohort: PriceCohort = {
  variant_id: "v1",
  variant_code: "RIZ_PARFUME",
  variant_name_fr: "Riz parfumé",
  canonical_base_unit: "kg",
  zone: "Matam",
  sample_count: 8,
  insufficient_data: false,
  confidence: "medium",
  freshness: "fresh",
  p25_gnf: 11000,
  median_gnf: 12000,
  p75_gnf: 13000,
  min_gnf: 10000,
  max_gnf: 14000,
  latest_observed_at: new Date().toISOString(),
  window_hours: 336,
  source_mix: { merchant_ask: 3, verified_procurement: 5 },
  movement: { comparable: false, reason: "INSUFFICIENT_COMPARISON_WINDOW" },
};

beforeEach(() => {
  rpcMock.mockReset();
  clearObservedPriceCache();
});

describe("R8 freshness contract mirrors the server vocabulary", () => {
  it("declares exactly none | fresh | aging | stale", () => {
    expect([...PRICE_FRESHNESS_VALUES]).toEqual(["none", "fresh", "aging", "stale"]);
  });

  it("gives every server state a distinct honest French label", () => {
    const labels = PRICE_FRESHNESS_VALUES.map(freshnessLabel);
    expect(new Set(labels).size).toBe(PRICE_FRESHNESS_VALUES.length);
    labels.forEach((l) => expect(l.length).toBeGreaterThan(0));
  });

  it("renders an honest aging label for server 'aging' (never 'date inconnue')", () => {
    render(<ObservedPriceBadge cohort={{ ...baseCohort, freshness: "aging" }} />);
    const node = screen.getByTestId("observed-price-freshness");
    expect(node.textContent).toBe("Observation vieillissante");
    expect(node.textContent).not.toMatch(/inconnue/i);
  });

  it("renders honest unknown-date truth for server 'none'", () => {
    render(<ObservedPriceBadge cohort={{ ...baseCohort, freshness: "none" }} />);
    expect(screen.getByTestId("observed-price-freshness").textContent).toBe(
      "Aucune date d'observation",
    );
  });

  it("does not invent a client-only freshness state", () => {
    // 'recent' / 'unknown' are NOT server states; they must not be modelled.
    expect(PRICE_FRESHNESS_VALUES).not.toContain("recent" as never);
    expect(PRICE_FRESHNESS_VALUES).not.toContain("unknown" as never);
    // An unexpected server value degrades to the honest no-date truth.
    expect(freshnessLabel("recent")).toBe("Aucune date d'observation");
  });
});

describe("R8 zone context", () => {
  it("treats all/unknown/empty as non-specific", () => {
    expect(isSpecificZone("Matam")).toBe(true);
    expect(isSpecificZone("all")).toBe(false);
    expect(isSpecificZone("unknown")).toBe(false);
    expect(isSpecificZone(null)).toBe(false);
  });

  it("renders the known zone in the badge", () => {
    render(<ObservedPriceBadge cohort={baseCohort} />);
    expect(screen.getByTestId("observed-price-zone").textContent).toBe("Zone : Matam");
  });

  it("renders 'Toutes zones' for the all sentinel and nothing for unknown", () => {
    expect(zoneLabel("all")).toBe("Toutes zones");
    expect(zoneLabel("unknown")).toBeNull();
    render(<ObservedPriceBadge cohort={{ ...baseCohort, zone: "unknown" }} />);
    expect(screen.queryByTestId("observed-price-zone")).toBeNull();
  });

  it("shows zone context on insufficient-data cohorts too", () => {
    render(
      <ObservedPriceBadge
        cohort={{ ...baseCohort, insufficient_data: true, confidence: "insufficient", sample_count: 2, min_samples: 5 }}
      />,
    );
    const box = screen.getByTestId("observed-price-insufficient");
    expect(box.textContent).toMatch(/Données insuffisantes/);
    expect(box.textContent).toMatch(/Matam/);
  });
});

describe("R8 client is server-sourced only", () => {
  it("calls the sanitized public RPC and caches the result", async () => {
    rpcMock.mockResolvedValue({
      data: { commodity_code: "RIZ", zone: "all", cohorts: [baseCohort], doctrine: "Prix observé sur ChopChop" },
      error: null,
    });
    const a = await fetchObservedPrices("RIZ");
    const b = await fetchObservedPrices("RIZ");
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock).toHaveBeenCalledWith("marche_price_observed_public", {
      p_commodity_code: "RIZ",
      p_zone: null,
    });
    expect(pickVariantCohort(a, "RIZ_PARFUME")?.median_gnf).toBe(12000);
    expect(b).toBe(a);
  });

  it("stays honest when the server returns nothing", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    expect(await fetchObservedPrices("HUILE")).toBeNull();
    render(<ObservedPriceBadge cohort={pickVariantCohort(null, "X")} />);
    expect(screen.getByTestId("observed-price-none").textContent).toMatch(
      /pas encore d'observation/,
    );
  });

  it("never renders a fabricated median when data is insufficient", () => {
    render(
      <ObservedPriceBadge
        cohort={{ ...baseCohort, insufficient_data: true, confidence: "insufficient", median_gnf: null, sample_count: 1, min_samples: 5 }}
      />,
    );
    expect(screen.queryByTestId("observed-price")).toBeNull();
    expect(screen.getByTestId("observed-price-insufficient").textContent).not.toMatch(/GNF/);
  });
});