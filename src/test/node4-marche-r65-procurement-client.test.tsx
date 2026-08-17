import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

const rpcMock = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...a) },
}));

import { ProcurementBasketSheet, type BasketLine } from "@/components/marche/ProcurementBasketSheet";
import {
  createProcurementRequestIdStore,
  procurementIntentKey,
  sanitizeLines,
  insufficientDataMessageFr,
  procurementErrorFr,
  quoteProcurement,
  authorizeProcurement,
} from "@/lib/marche/procurement";

const LINES: BasketLine[] = [
  {
    commodity_code: "RIZ",
    variant_code: "RIZ_PARFUME",
    option_code: "SAC_25KG",
    qty: 1,
    label_fr: "Riz · Parfumé",
    option_label_fr: "Sac 25 kg",
  },
];

const availableQuote = {
  lines: [],
  line_count: 1,
  item_count: 1,
  currency: "GNF",
  estimate_status: "available",
  estimate_basis: "observed_procurement",
  estimated_subtotal_gnf: 300000,
  estimate_confidence: "medium",
  estimate_sample_count: 5,
  estimate_freshness_hours: 12,
  estimate_unavailable_reason: null,
  min_samples: 3,
  observation_window_hours: 336,
  authorization_allowed: true,
  min_ceiling_gnf: 300000,
  max_ceiling_gnf: 20000000,
  disclaimer_fr: "Estimation — le prix réel au marché peut varier.",
};

const insufficientQuote = {
  ...availableQuote,
  estimate_status: "insufficient_data",
  estimated_subtotal_gnf: null,
  estimate_confidence: null,
  estimate_unavailable_reason: "NO_RECENT_PROCUREMENT_OBSERVATIONS",
  authorization_allowed: false,
  min_ceiling_gnf: null,
};

beforeEach(() => {
  rpcMock.mockReset();
  localStorage.clear();
});

describe("R6.5 client — server sovereignty", () => {
  it("never sends merchant or price fields to the server", () => {
    const dirty = [{ ...LINES[0], listing_id: "x", price_gnf: 999 }] as unknown as BasketLine[];
    expect(sanitizeLines(dirty)[0]).toEqual({
      commodity_code: "RIZ",
      variant_code: "RIZ_PARFUME",
      option_code: "SAC_25KG",
      qty: 1,
    });
  });

  it("quote passes only the sanitized basket payload", async () => {
    rpcMock.mockResolvedValue({ data: availableQuote, error: null });
    await quoteProcurement(LINES);
    expect(rpcMock).toHaveBeenCalledWith("marche_procurement_quote", {
      p: { lines: [{ commodity_code: "RIZ", variant_code: "RIZ_PARFUME", option_code: "SAC_25KG", qty: 1 }] },
    });
  });

  it("surfaces server refusal instead of inventing success", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA" } });
    await expect(
      authorizeProcurement({ lines: LINES, ceilingGnf: 1000, clientRequestId: "k" }),
    ).rejects.toThrow("PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA");
  });

  it("maps canonical server errors to honest French copy", () => {
    expect(procurementErrorFr("PROCUREMENT_CEILING_BELOW_ESTIMATE")).toMatch(/au moins égal à l'estimation/);
    expect(insufficientDataMessageFr(insufficientQuote)).toMatch(/pas assez de relevés/);
  });
});

describe("R6.5 client — durable request identity", () => {
  it("reuses the same key for an unchanged basket + ceiling", () => {
    const s = createProcurementRequestIdStore("t");
    const a = s.idFor(LINES, 300000);
    expect(s.idFor(LINES, 300000)).toBe(a);
    expect(createProcurementRequestIdStore("t").idFor(LINES, 300000)).toBe(a);
  });

  it("issues a new key when basket or ceiling materially changes", () => {
    const s = createProcurementRequestIdStore("t2");
    const a = s.idFor(LINES, 300000);
    expect(s.idFor(LINES, 330000)).not.toBe(a);
    expect(s.idFor([{ ...LINES[0], qty: 2 }], 300000)).not.toBe(a);
  });

  it("fingerprint is order-insensitive", () => {
    const l2 = [{ ...LINES[0], option_code: "B" }, { ...LINES[0], option_code: "A" }];
    const l1 = [{ ...LINES[0], option_code: "A" }, { ...LINES[0], option_code: "B" }];
    expect(procurementIntentKey(l1, 5)).toBe(procurementIntentKey(l2, 5));
  });
});

describe("R6.5 basket UI laws", () => {
  const renderSheet = () =>
    render(
      <ProcurementBasketSheet open lines={LINES} onOpenChange={() => {}} onRemove={() => {}} />,
    );

  it("shows honest insufficient-data state and blocks authorization", async () => {
    rpcMock.mockResolvedValue({ data: insufficientQuote, error: null });
    renderSheet();
    await screen.findByTestId("insufficient-data");
    expect(screen.queryByTestId("estimate-amount")).toBeNull();
    expect(screen.getByTestId("authorize-button")).toBeDisabled();
  });

  it("distinguishes estimate from authorized maximum and explains settlement", async () => {
    rpcMock.mockResolvedValue({ data: availableQuote, error: null });
    renderSheet();
    await screen.findByTestId("estimate-amount");
    expect(screen.getByTestId("ceiling-amount")).toBeInTheDocument();
    expect(screen.getByTestId("estimate-amount").textContent).not.toBe("");
    fireEvent.click(screen.getByTestId("buffer-10"));
    await waitFor(() =>
      expect(screen.getByTestId("ceiling-amount").textContent).not.toBe(
        screen.getByTestId("estimate-amount").textContent,
      ),
    );
    expect(screen.getByText(/dépense réelle/i)).toBeInTheDocument();
    expect(screen.getByText(/pas un prix d'achat garanti/i)).toBeInTheDocument();
  });

  it("shows the server refusal when authorization is rejected", async () => {
    rpcMock.mockImplementation((name: string) =>
      name === "marche_procurement_quote"
        ? Promise.resolve({ data: availableQuote, error: null })
        : Promise.resolve({ data: null, error: { message: "PROCUREMENT_CEILING_BELOW_ESTIMATE" } }),
    );
    renderSheet();
    await screen.findByTestId("authorize-button");
    fireEvent.click(screen.getByTestId("authorize-button"));
    const err = await screen.findByTestId("auth-error");
    expect(err.textContent).toMatch(/estimation/i);
  });

  it("repeated taps reuse one client_request_id (no duplicate authorization)", async () => {
    let resolveAuth: (v: unknown) => void = () => {};
    rpcMock.mockImplementation((name: string) =>
      name === "marche_procurement_quote"
        ? Promise.resolve({ data: availableQuote, error: null })
        : new Promise((r) => {
            resolveAuth = r;
          }),
    );
    renderSheet();
    await screen.findByTestId("authorize-button");
    fireEvent.click(screen.getByTestId("authorize-button"));
    fireEvent.click(screen.getByTestId("authorize-button"));
    fireEvent.click(screen.getByTestId("authorize-button"));
    const authCalls = rpcMock.mock.calls.filter((c) => c[0] === "marche_procurement_authorize");
    expect(authCalls.length).toBe(1);
    resolveAuth({ data: { ...availableQuote, id: "r1", authorized_ceiling_gnf: 300000 }, error: null });
    await waitFor(() => expect(screen.getByTestId("procurement-authorized")).toBeInTheDocument());
  });

  it("exposes no shopper, substitution or settlement controls to the customer", async () => {
    rpcMock.mockResolvedValue({ data: availableQuote, error: null });
    const { container } = renderSheet();
    await screen.findByTestId("estimate-amount");
    expect(container.textContent).not.toMatch(/substitut|shopper|régler la dépense|settle/i);
  });
});
