import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

const rpcMock = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...a) },
}));

import { ObservedPriceBadge } from "@/components/marche/ObservedPriceBadge";
import {
  clearObservedPriceCache,
  pickVariantCohort,
  baseUnitLabel,
  type ObservedPriceRead,
} from "@/lib/marche/priceIntelligence";

const read = (cohorts: unknown[]): ObservedPriceRead =>
  ({
    commodity_code: "riz",
    zone: "all",
    doctrine: "Prix observé sur ChopChop",
    cohorts,
  }) as ObservedPriceRead;

const solid = {
  variant_code: "v1",
  variant_name_fr: "Riz parfumé",
  canonical_base_unit: "kg",
  zone: "Matam",
  sample_count: 6,
  insufficient_data: false,
  confidence: "medium",
  freshness: "fresh",
  median_gnf: 12000,
  p25_gnf: 11000,
  p75_gnf: 13000,
  movement: { comparable: true, delta_gnf: 1000, delta_pct: 9.09 },
};

const thin = {
  variant_code: "v1",
  variant_name_fr: "Riz parfumé",
  canonical_base_unit: "kg",
  zone: "Kaloum",
  sample_count: 1,
  insufficient_data: true,
  confidence: "insufficient",
  freshness: "fresh",
  reason: "INSUFFICIENT_OBSERVATIONS",
};

beforeEach(() => {
  rpcMock.mockReset();
  clearObservedPriceCache();
});

describe("R8 observed price client surface", () => {
  it("reads observed prices from the server RPC only", async () => {
    rpcMock.mockResolvedValue({ data: read([solid]), error: null });
    render(<ObservedPriceBadge commodityCode="riz" variantCode="v1" zone="Matam" />);
    await waitFor(() => expect(rpcMock).toHaveBeenCalled());
    expect(rpcMock.mock.calls[0][0]).toBe("marche_price_observed_public");
    expect(rpcMock.mock.calls[0][1]).toEqual({ p_commodity_code: "riz", p_zone: "Matam" });
  });

  it("renders the observed median, band and honest doctrine", async () => {
    rpcMock.mockResolvedValue({ data: read([solid]), error: null });
    render(<ObservedPriceBadge commodityCode="riz" variantCode="v1" />);
    expect(await screen.findByText(/observé sur ChopChop/i)).toBeInTheDocument();
    expect(screen.getByText(/Fourchette observée/i)).toBeInTheDocument();
    expect(screen.getByText(/6 relevés/i)).toBeInTheDocument();
    expect(screen.getByText(/pas un prix officiel ni garanti/i)).toBeInTheDocument();
  });

  it("never invents a number when evidence is insufficient", async () => {
    rpcMock.mockResolvedValue({ data: read([thin]), error: null });
    render(<ObservedPriceBadge commodityCode="riz" variantCode="v1" zone="Kaloum" />);
    expect(
      await screen.findByText(/Pas encore assez de relevés/i),
    ).toBeInTheDocument();
    expect(screen.queryByText(/observé sur ChopChop/i)).toBeNull();
  });

  it("stays silent when the server returns no cohort for the variant", async () => {
    rpcMock.mockResolvedValue({ data: read([]), error: null });
    render(<ObservedPriceBadge commodityCode="riz" variantCode="v9" />);
    expect(await screen.findByText(/Pas encore assez de relevés/i)).toBeInTheDocument();
  });

  it("degrades honestly when the read fails", async () => {
    rpcMock.mockRejectedValue(new Error("network"));
    render(<ObservedPriceBadge commodityCode="riz" variantCode="v1" />);
    expect(await screen.findByText(/Pas encore assez de relevés/i)).toBeInTheDocument();
  });

  it("prefers a usable cohort and keeps unit labels non-comparable-safe", () => {
    const picked = pickVariantCohort(read([thin, solid]), "v1");
    expect(picked?.sample_count).toBe(6);
    expect(baseUnitLabel("unit:tas")).toBe("tas");
    expect(baseUnitLabel("l")).toBe("L");
  });
});