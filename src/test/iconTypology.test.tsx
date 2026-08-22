import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { ServicesView } from "@/components/views/ServicesView";
import { ServiceIcon } from "@/components/services/ServiceIcon";
import { Car } from "lucide-react";
import {
  SERVICE_ICON_ASSETS,
  SERVICE_ICON_TUNING,
  getServiceIconAsset,
  isServiceGlyphPlaceholder,
} from "@/lib/services/serviceIcons";

vi.mock("@/lib/flags/useFeatureFlag", () => ({
  usePublicPaymentProductName: () => "Chop Pay",
  usePublicPaymentProductSubtitle: () => "Payer et recharger",
  useEnvoyerEnabled: () => true,
  useTaxiEnabled: () => true,
  usePublicWalletEnabled: () => true,
  useFlagsReady: () => true,
  useFeatureFlag: () => true,
}));

const TRANSACTIONAL = ["moto", "toktok", "auto", "parcel", "food", "market", "wallet", "scan"];
const UTILITY = ["merchant", "driver", "help"];

function renderServices(onActionClick = vi.fn()) {
  render(
    <MemoryRouter>
      <ServicesView onActionClick={onActionClick} />
    </MemoryRouter>,
  );
  return onActionClick;
}

describe("PASS 1 — global icon typology", () => {
  it("registers branded artwork for every transactional service except the Taxi placeholder", () => {
    for (const id of TRANSACTIONAL) {
      if (isServiceGlyphPlaceholder(id)) {
        expect(getServiceIconAsset(id)).toBeUndefined();
      } else {
        expect(getServiceIconAsset(id), `missing asset for ${id}`).toBeTruthy();
      }
    }
  });

  it("points branded services at their own canonical asset (no borrowing)", () => {
    const assets = Object.entries(SERVICE_ICON_ASSETS);
    for (const [id, src] of assets) {
      expect(String(src)).toContain(
        { moto: "moto", toktok: "toktok", parcel: "envoyer", food: "repas", market: "marche", wallet: "wallet", scan: "scanner" }[id]!,
      );
    }
    // Taxi must never borrow Moto art.
    expect(SERVICE_ICON_ASSETS).not.toHaveProperty("auto");
    expect(isServiceGlyphPlaceholder("auto")).toBe(true);
  });

  it("keeps optical tuning centralized for every canonical icon id", () => {
    for (const id of TRANSACTIONAL) {
      expect(SERVICE_ICON_TUNING[id as keyof typeof SERVICE_ICON_TUNING]).toBeDefined();
    }
  });

  it("renders transactional tiles under the Family-A contract", () => {
    renderServices();
    for (const id of TRANSACTIONAL) {
      const tile = document.querySelector(`[data-service-id="${id}"]`);
      expect(tile, `missing tile ${id}`).toBeTruthy();
      expect(tile!.getAttribute("data-icon-family")).toBe("service");
      expect(tile!.getAttribute("data-icon-asset")).toBe(id === "auto" ? "glyph" : "branded");
    }
  });

  it("renders entry/utility tiles under the Family-B contract", () => {
    renderServices();
    for (const id of UTILITY) {
      const tile = document.querySelector(`[data-service-id="${id}"]`);
      expect(tile, `missing tile ${id}`).toBeTruthy();
      expect(tile!.getAttribute("data-icon-family")).toBe("entry");
      expect(tile!.getAttribute("data-icon-asset")).toBe("glyph");
      // Neutral circular chip, never the branded square.
      expect(tile!.querySelector(".rounded-full")).toBeTruthy();
      expect(tile!.querySelector("img")).toBeNull();
    }
  });

  it("gives Family-A tiles the branded square chip", () => {
    renderServices();
    const moto = document.querySelector('[data-service-id="moto"]')!;
    expect(moto.querySelector(".rounded-xl")).toBeTruthy();
    expect(moto.querySelector("img")).toBeTruthy();
  });

  it("renders the Taxi glyph placeholder inside the Family-A chip", () => {
    render(<ServiceIcon id="auto" family="service" Glyph={Car} />);
    const chip = document.querySelector(".rounded-xl")!;
    expect(chip).toBeTruthy();
    expect(chip.querySelector("svg")).toBeTruthy();
    expect(document.querySelector("img")).toBeNull();
  });

  it("does not change click behaviour or labels", () => {
    const onActionClick = renderServices();
    expect(screen.getByLabelText("Course Taxi")).toBeTruthy();
    expect(screen.getByLabelText("Course Moto")).toBeTruthy();
    (screen.getByLabelText("Course Moto") as HTMLElement).click();
    expect(onActionClick).toHaveBeenCalledWith("moto");
  });

  it("keeps chip artwork decorative (a11y name lives on the button)", () => {
    renderServices();
    for (const img of Array.from(document.querySelectorAll("img"))) {
      expect(img.getAttribute("alt")).toBe("");
    }
  });
});
