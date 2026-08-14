import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { repasAvailabilityLabel, repasBlockedLabel, REPAS_BLOCKED_REASON_LABEL } from "@/lib/repas/discovery";

const read = (p: string) => readFileSync(`${process.cwd()}/${p}`, "utf8");

const FAKE_RESTAURANTS = [
  "Chez Mama Fatoumata",
  "Grillades du Port",
  "Le Palmier",
  "Café Conakry",
  "La Terrasse",
  "Pâtisserie Belle Vue",
];

describe("R8 — Repas discovery truth (client surfaces)", () => {
  const foodView = read("src/components/views/FoodView.tsx");
  const card = read("src/components/food/RestaurantCard.tsx");
  const detail = read("src/components/food/RepasRestaurantDetail.tsx");

  it("1. FoodView carries no seeded fake supply or marketing claims", () => {
    for (const n of FAKE_RESTAURANTS) expect(foodView).not.toContain(n);
    expect(foodView).not.toContain("Livraison en 15 min");
    expect(foodView).not.toContain("Tendance ce soir");
    expect(foodView).not.toContain("Restaurants notés 4.5+");
  });

  it("2. no fake rating / delivery-ETA / distance dimensions are rendered", () => {
    for (const raw of [foodView, card, detail]) {
      const src = raw;
      expect(src.replace(/\/\*[\s\S]*?\*\//g, "")).not.toMatch(/rating/i);
      expect(src).not.toMatch(/deliveryTime|delivery_eta|eta_min/);
      expect(src).not.toMatch(/distanceKm|distance_km/);
    }
  });

  it("3. empty states distinguish no supply from no search result", () => {
    expect(foodView).toContain("Aucun restaurant disponible pour le moment");
    expect(foodView).toContain("Aucun résultat");
  });

  it("4. no Unsplash fallback; neutral placeholder instead", () => {
    for (const src of [foodView, card, detail]) expect(src).not.toContain("images.unsplash.com");
    expect(detail).toContain("repas-cover-placeholder");
    expect(card).toContain("UtensilsCrossed");
  });

  it("5. the prep estimate is explicitly labelled as preparation", () => {
    expect(card).toContain("Préparation ~{r.prep_time_min} min");
    expect(card).not.toMatch(/Livraison\s*~/);
  });

  it("6. canonical detail resolution gates add/cart/checkout", () => {
    expect(detail).toContain('useState<"loading" | "found" | "unavailable">');
    expect(detail).toContain('resolution === "found" && (detail?.orderable_now ?? false)');
    expect(detail).not.toContain("const orderableNow = view.orderable_now");
    expect(detail).toContain("Ce restaurant n'est plus disponible.");
  });

  it("7. availability / blocked labels stay truthful", () => {
    expect(REPAS_BLOCKED_REASON_LABEL.not_published).toBe("Ce restaurant n'est pas encore publié.");
    expect(repasBlockedLabel("closed")).toBe("Restaurant fermé pour le moment.");
    expect(repasBlockedLabel("no_menu")).toBe("Menu pas encore renseigné.");
    expect(repasBlockedLabel(null)).toBeNull();
    const base = { orderable_now: false, blocked_reason: null } as never;
    expect(repasAvailabilityLabel({ ...(base as object), orderable_now: true } as never)).toBe("Commande ouverte");
    expect(repasAvailabilityLabel({ ...(base as object), blocked_reason: "closed" } as never)).toBe("Fermé");
    expect(repasAvailabilityLabel({ ...(base as object), blocked_reason: "no_available_items" } as never)).toBe("Plats épuisés");
    expect(repasAvailabilityLabel({ ...(base as object), blocked_reason: "not_published" } as never)).toBe("Indisponible");
  });
});
