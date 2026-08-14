import { describe, it, expect, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import {
  readDestinationDraft,
  writeDestinationDraft,
  clearDestinationDraft,
  repasLocationQualityLabel,
} from "@/lib/repas/destinationDraft";

const detail = readFileSync("src/components/food/RepasRestaurantDetail.tsx", "utf8");
const panel = readFileSync("src/components/repas/RepasOrderTrackingPanel.tsx", "utf8");
const orders = readFileSync("src/lib/repas/orders.ts", "utf8");

describe("Repas R11 — Conakry destination truth", () => {
  beforeEach(() => clearDestinationDraft());

  it("the GPS button never overwrites the typed place label", () => {
    expect(detail).not.toContain("Position actuelle (");
    expect(detail).toContain("setLocationSource(\"gps\")");
  });

  it("landmark and instructions are first-class checkout inputs", () => {
    expect(detail).toContain("Repère le plus proche");
    expect(detail).toContain("Indications pour le coursier");
  });

  it("the destination is sent to the canonical server RPC", () => {
    expect(orders).toContain("p_delivery_landmark");
    expect(orders).toContain("p_delivery_instructions");
    expect(orders).toContain("p_location_source");
  });

  it("a pickup order sends no destination at all", () => {
    expect(detail).toContain('deliveryLandmark: fulfillment === "delivery"');
    expect(detail).toContain('locationSource: fulfillment === "delivery"');
  });

  it("the draft survives a reload and is cleared once committed", () => {
    writeDestinationDraft({
      restaurantId: "r1",
      label: "Kipé",
      landmark: "près de Prima Center",
      instructions: "portail bleu",
      lat: 9.53,
      lng: -13.67,
      source: "gps",
    });
    const d = readDestinationDraft("r1");
    expect(d?.landmark).toBe("près de Prima Center");
    expect(d?.lat).toBe(9.53);
    expect(readDestinationDraft("other")).toBeNull();
    clearDestinationDraft();
    expect(readDestinationDraft("r1")).toBeNull();
  });

  it("an empty draft is never persisted", () => {
    writeDestinationDraft({
      restaurantId: "r1", label: "", landmark: "", instructions: "",
      lat: null, lng: null, source: "unspecified",
    });
    expect(readDestinationDraft("r1")).toBeNull();
  });

  it("the draft carries no money, order identity or pricing", () => {
    writeDestinationDraft({
      restaurantId: "r1", label: "Kipé", landmark: "", instructions: "",
      lat: null, lng: null, source: "typed",
    });
    const raw = JSON.stringify(readDestinationDraft("r1"));
    expect(raw).not.toMatch(/gnf|total|price|order_id/i);
  });

  it("location quality is labelled honestly and never invented", () => {
    expect(repasLocationQualityLabel("gps_verified")).toBe("Position GPS confirmée");
    expect(repasLocationQualityLabel("landmark_assisted")).toMatch(/pas de point GPS/);
    expect(repasLocationQualityLabel(null)).toBeNull();
    expect(repasLocationQualityLabel("something_else")).toBeNull();
  });

  it("tracking degrades visibly instead of freezing silently", () => {
    expect(panel).toContain("Hors ligne : dernier état connu affiché.");
    expect(panel).toContain("FALLBACK_POLL_MAX");
  });

  it("the fallback refresh is bounded and stops on terminal orders", () => {
    expect(panel).toMatch(/if \(!tracking \|\| tracking\.terminal\) return;/);
    expect(panel).toMatch(/pollCount\.current >= FALLBACK_POLL_MAX/);
  });

  it("the tracking panel renders the frozen destination, not a local guess", () => {
    expect(panel).toContain("tracking.destination");
    expect(panel).toContain("Cette destination est figée pour cette commande.");
  });
});
