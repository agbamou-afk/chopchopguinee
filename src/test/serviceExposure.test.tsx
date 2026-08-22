/**
 * PASS 2 — FEATURE FLAGS AS CUSTOMER PRODUCT-EXPOSURE SOURCE OF TRUTH.
 * Adversarial coverage of the owner-approved exposure law.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import {
  SERVICE_EXPOSURE_RULES,
  isActionExposed,
  resolveExposureAction,
  type ExposureActionId,
} from "@/lib/services/serviceExposure";
import {
  CLIENT_KNOWN_FLAGS,
  CLIENT_FLAG_DEFAULTS,
  type FlagKey,
} from "@/lib/flags/featureFlags";

/** Live flag values driven per-test. */
const flags: Record<string, boolean> = {};
let ready = true;

vi.mock("@/lib/flags/featureFlags", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/flags/featureFlags")>();
  return { ...actual, getFlag: (k: string) => flags[k] ?? false };
});

vi.mock("@/lib/flags/useFeatureFlag", () => ({
  useFeatureFlag: (k: string) => flags[k] ?? false,
  useFlagsReady: () => ready,
  usePublicPaymentProductName: () => "Chop Pay",
  usePublicPaymentProductSubtitle: () => "Payer et recharger",
  usePublicWalletEnabled: () => flags.wallet_public_enabled ?? false,
  useEnvoyerEnabled: () => flags.envoyer_enabled ?? false,
  useTaxiEnabled: () => flags.taxi ?? false,
}));

import { ServicesView } from "@/components/views/ServicesView";
import { QuickActions } from "@/components/home/QuickActions";
import { PrimaryActionGrid } from "@/components/home/PrimaryActionGrid";
import { ExposureRouteGuard } from "@/components/services/ExposureRouteGuard";

const ALL_ON: Record<string, boolean> = {
  service_moto_enabled: true,
  service_toktok_enabled: true,
  service_repas_enabled: true,
  service_marche_enabled: true,
  service_scan_enabled: true,
  merchant_recruitment_enabled: true,
  driver_recruitment_enabled: true,
  taxi: true,
  envoyer_enabled: true,
  chop_pay_enabled: true,
  wallet_public_enabled: false,
};

function setFlags(overrides: Record<string, boolean> = {}) {
  for (const k of Object.keys(flags)) delete flags[k];
  Object.assign(flags, ALL_ON, overrides);
}

beforeEach(() => {
  ready = true;
  setFlags();
});

const renderServices = () =>
  render(
    <MemoryRouter>
      <ServicesView onActionClick={vi.fn()} />
    </MemoryRouter>,
  );

describe("PASS 2 — exposure registry law", () => {
  it("declares an exposure rule for every canonical customer action", () => {
    const ids: ExposureActionId[] = [
      "moto", "toktok", "auto", "parcel", "food", "market",
      "wallet", "scan", "merchant", "driver", "help",
    ];
    for (const id of ids) expect(SERVICE_EXPOSURE_RULES[id]).toBeDefined();
  });

  it("registers every exposure flag in the client flag registry", () => {
    for (const rule of Object.values(SERVICE_EXPOSURE_RULES)) {
      for (const f of rule.flags) expect(CLIENT_KNOWN_FLAGS).toContain(f);
    }
  });

  it("defaults the seven new PASS 2 flags to ON", () => {
    const news: FlagKey[] = [
      "service_moto_enabled", "service_toktok_enabled", "service_repas_enabled",
      "service_marche_enabled", "service_scan_enabled",
      "merchant_recruitment_enabled", "driver_recruitment_enabled",
    ];
    for (const f of news) expect(CLIENT_FLAG_DEFAULTS[f]).toBe(true);
  });

  it("never lets a sub-feature flag control a top-level entry", () => {
    const forbidden = [
      "om_topup_enabled", "om_checkout_enabled", "om_direct_checkout_enabled",
      "om_ride_checkout_enabled", "om_repas_checkout_enabled",
      "om_marche_checkout_enabled", "om_sandbox_enabled", "om_environment",
      "om_provider_mode", "driver_balance_gate_enabled",
      "envoyer_declared_value_enabled", "envoyer_claims_enabled",
    ];
    const used = Object.values(SERVICE_EXPOSURE_RULES).flatMap((r) => r.flags as string[]);
    for (const f of forbidden) expect(used).not.toContain(f);
  });

  it("keeps support exposed and resolves legacy aliases", () => {
    setFlags({
      service_moto_enabled: false, service_toktok_enabled: false,
      service_repas_enabled: false, service_marche_enabled: false,
      service_scan_enabled: false, taxi: false, envoyer_enabled: false,
      chop_pay_enabled: false, wallet_public_enabled: false,
    });
    expect(isActionExposed("help")).toBe(true);
    expect(isActionExposed("support")).toBe(true);
    expect(resolveExposureAction("send")).toBe("wallet");
    // Non-product router actions are never hidden by product flags.
    expect(isActionExposed("services")).toBe(true);
    expect(isActionExposed("orders")).toBe(true);
  });
});

describe("PASS 2 — discovery surfaces hide disabled products", () => {
  it("renders every product entry when all flags are ON", () => {
    renderServices();
    for (const label of ["Course Moto", "Course Bonbonna", "Course Taxi", "Envoyer", "Repas", "Marché"]) {
      expect(screen.getAllByText(new RegExp(label, "i")).length).toBeGreaterThan(0);
    }
  });

  it("hides Marché entirely — no placeholder, no disabled tile — when its flag is OFF", () => {
    setFlags({ service_marche_enabled: false });
    renderServices();
    expect(screen.queryByText(/Marché/i)).toBeNull();
    expect(screen.queryByText(/Bientôt disponible/i)).toBeNull();
    expect(document.querySelector('[aria-disabled="true"]')).toBeNull();
  });

  it("hides Taxi and Envoyer when their existing flags are OFF", () => {
    setFlags({ taxi: false, envoyer_enabled: false });
    renderServices();
    expect(screen.queryByText(/Course Taxi/i)).toBeNull();
    expect(screen.queryByText(/^Envoyer$/i)).toBeNull();
  });

  it("never renders a 'Bientôt disponible' discovery card in any state", () => {
    setFlags({ service_repas_enabled: false, service_scan_enabled: false });
    renderServices();
    expect(screen.queryByText(/Bientôt disponible/i)).toBeNull();
  });

  it("hides the home rail entries whose flags are OFF", () => {
    setFlags({ service_repas_enabled: false });
    render(<QuickActions onActionClick={vi.fn()} />);
    expect(screen.queryByText("Repas")).toBeNull();
    expect(screen.getByText("Course")).toBeTruthy();
  });

  it("hides the public payment tile when the public product flags are OFF", () => {
    setFlags({ chop_pay_enabled: false, wallet_public_enabled: false });
    render(<PrimaryActionGrid onAction={vi.fn()} />);
    expect(screen.queryByText(/Chop Pay/i)).toBeNull();
  });

  it("keeps the payment tile visible when only the legacy wallet alias is ON", () => {
    setFlags({ chop_pay_enabled: false, wallet_public_enabled: true });
    render(<PrimaryActionGrid onAction={vi.fn()} />);
    expect(screen.getAllByText(/Chop Pay/i).length).toBeGreaterThan(0);
  });
});

describe("PASS 2 — recruitment independence", () => {
  it("keeps recruitment visible when all transactional services are OFF", () => {
    setFlags({
      service_moto_enabled: false, service_toktok_enabled: false,
      service_repas_enabled: false, service_marche_enabled: false,
      service_scan_enabled: false, taxi: false, envoyer_enabled: false,
    });
    renderServices();
    expect(screen.getAllByText(/Devenir marchand/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Devenir chauffeur/i).length).toBeGreaterThan(0);
    // Aide is never hidden.
    expect(screen.getAllByText(/Aide/i).length).toBeGreaterThan(0);
  });

  it("hides recruitment entries independently of transactional services", () => {
    setFlags({ merchant_recruitment_enabled: false, driver_recruitment_enabled: false });
    renderServices();
    expect(screen.queryByText(/Devenir marchand/i)).toBeNull();
    expect(screen.queryByText(/Devenir chauffeur/i)).toBeNull();
    expect(screen.getAllByText(/Course Moto/i).length).toBeGreaterThan(0);
  });
});

describe("PASS 2 — anti-flicker and deep-link guards", () => {
  it("paints a neutral skeleton (never a disabled product) before flags resolve", () => {
    ready = false;
    setFlags({ service_marche_enabled: false });
    renderServices();
    expect(screen.queryByText(/Marché/i)).toBeNull();
    expect(screen.queryByText(/Course Moto/i)).toBeNull();
    expect(document.querySelector('[aria-busy="true"]')).toBeTruthy();
  });

  it("blocks a direct route hit for a hidden product and redirects safely", () => {
    setFlags({ merchant_recruitment_enabled: false });
    render(
      <MemoryRouter initialEntries={["/devenir-marchand"]}>
        <ExposureRouteGuard action="merchant">
          <div>MERCHANT_APPLY</div>
        </ExposureRouteGuard>
      </MemoryRouter>,
    );
    expect(screen.queryByText("MERCHANT_APPLY")).toBeNull();
  });

  it("renders the guarded route when the flag is ON", () => {
    render(
      <MemoryRouter initialEntries={["/devenir-marchand"]}>
        <ExposureRouteGuard action="merchant">
          <div>MERCHANT_APPLY</div>
        </ExposureRouteGuard>
      </MemoryRouter>,
    );
    expect(screen.getByText("MERCHANT_APPLY")).toBeTruthy();
  });

  it("renders nothing (no flash) while flags are unresolved on a guarded route", () => {
    ready = false;
    render(
      <MemoryRouter>
        <ExposureRouteGuard action="merchant">
          <div>MERCHANT_APPLY</div>
        </ExposureRouteGuard>
      </MemoryRouter>,
    );
    expect(screen.queryByText("MERCHANT_APPLY")).toBeNull();
  });

  it("refuses hidden actions at the central action router (stale-UI bypass)", () => {
    setFlags({ service_marche_enabled: false, envoyer_enabled: false });
    expect(isActionExposed("market")).toBe(false);
    expect(isActionExposed("marche")).toBe(false);
    expect(isActionExposed("parcel")).toBe(false);
    expect(isActionExposed("moto")).toBe(true);
  });
});
