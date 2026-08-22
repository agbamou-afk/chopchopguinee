/**
 * PASS 2 micro-closeout — SEAM 3.
 * Top-level public payment entry (WalletHero) obeys exposure law, and the
 * Home recruitment cards use canonical PASS 1 Family-B typology.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

const flags: Record<string, boolean> = {};
let ready = true;

vi.mock("@/lib/flags/featureFlags", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/flags/featureFlags")>();
  return { ...actual, getFlag: (k: string) => flags[k] ?? false, flagsReady: () => ready };
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

// Heavy/non-presentational dependencies stubbed — this is a presentation test.
vi.mock("@/hooks/useWallet", () => ({
  useWallet: () => ({ available: 12000, loading: false, error: null, wallet: { status: "active" } }),
}));
vi.mock("@/hooks/useCustomerMissionAlerts", () => ({ useCustomerMissionAlerts: () => undefined }));
vi.mock("@/hooks/useNearbyAvailableDrivers", () => ({
  useNearbyAvailableDrivers: () => ({ drivers: [], loading: false }),
}));
vi.mock("@/lib/location/useLiveUserLocation", () => ({
  useLiveUserLocation: () => ({
    coords: null,
    fallbackCenter: { lat: 9.5, lng: -13.7 },
    isRealLocation: false,
    status: "idle",
  }),
}));
vi.mock("@/contexts/AuthContext", () => ({ useAuth: () => ({ user: null }) }));
vi.mock("@/contexts/AppEnvContext", () => ({ useAppEnv: () => ({ lowDataMode: true }) }));
vi.mock("@/lib/repas/discovery", () => ({ discoverRestaurants: async () => [] }));
vi.mock("@/components/activity/RecentActivityPeek", () => ({ RecentActivityPeek: () => null }));
vi.mock("@/components/home/PromoCarousel", () => ({ PromoCarousel: () => null }));

import { UserHome } from "@/components/views/UserHome";
import { ENTRY_CHIP_CLASS } from "@/lib/services/serviceIcons";

const ALL_ON: Record<string, boolean> = {
  service_moto_enabled: true,
  service_toktok_enabled: true,
  service_repas_enabled: true,
  service_marche_enabled: true,
  service_scan_enabled: true,
  merchant_recruitment_enabled: true,
  driver_recruitment_enabled: true,
  taxi: false,
  envoyer_enabled: true,
  chop_pay_enabled: false,
  wallet_public_enabled: false,
};

function setFlags(overrides: Record<string, boolean> = {}) {
  for (const k of Object.keys(flags)) delete flags[k];
  Object.assign(flags, ALL_ON, overrides);
}

function renderHome() {
  render(
    <MemoryRouter>
      <UserHome onActionClick={vi.fn()} onToggleDriverMode={vi.fn()} />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  ready = true;
  setFlags();
});

describe("SEAM 3 — WalletHero obeys public payment exposure", () => {
  it("renders nothing for the wallet entry when both public payment flags are OFF", () => {
    setFlags({ chop_pay_enabled: false, wallet_public_enabled: false });
    renderHome();
    expect(screen.queryByText(/Solde disponible|Recharger|portefeuille/i)).toBeNull();
  });

  it("renders the wallet hero when chop_pay_enabled is ON", () => {
    setFlags({ chop_pay_enabled: true });
    renderHome();
    expect(screen.getAllByText(/Recharger/i).length).toBeGreaterThan(0);
  });

  it("renders the wallet hero when only the legacy wallet_public_enabled alias is ON", () => {
    setFlags({ wallet_public_enabled: true });
    renderHome();
    expect(screen.getAllByText(/Recharger/i).length).toBeGreaterThan(0);
  });

  it("does not flash a wallet skeleton before flags resolve", () => {
    ready = false;
    setFlags({ chop_pay_enabled: true });
    renderHome();
    expect(screen.queryByText(/Recharger/i)).toBeNull();
  });
});

describe("SEAM 3 — Home recruitment cards use canonical Family-B typology", () => {
  it("renders both recruitment chips through the shared entry contract", () => {
    renderHome();
    expect(screen.getByText("Devenir marchand")).toBeTruthy();
    expect(screen.getByText("Devenir chauffeur")).toBeTruthy();
    const chips = document.querySelectorAll(`div.${CSS.escape(ENTRY_CHIP_CLASS.split(" ")[0])}`);
    expect(chips.length).toBeGreaterThan(0);
    // No ad-hoc rounded-square colored chips left on those cards.
    expect(document.querySelector(".rounded-xl.bg-secondary\\/20")).toBeNull();
  });

  it("keeps the recruitment cards gated by their own recruitment flags", () => {
    setFlags({ merchant_recruitment_enabled: false, driver_recruitment_enabled: false });
    renderHome();
    expect(screen.queryByText("Devenir marchand")).toBeNull();
    expect(screen.queryByText("Devenir chauffeur")).toBeNull();
  });
});
