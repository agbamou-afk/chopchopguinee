import { describe, it, expect, beforeEach, vi } from "vitest";
import { backoffDelayMs, boundedPoll, isLostResponseError } from "@/lib/net/boundedPoll";
import {
  clearBasketDraft,
  hasUsableDestination,
  loadBasketDraft,
  normalizeDraft,
  saveBasketDraft,
} from "@/lib/marche/basketDraft";
import { orderIntentKey, createOrderRequestIdStore } from "@/lib/marche/orderRequestId";
import { destinationQualityLabel, translateOrderError } from "@/lib/marche/orders";

describe("R13 — bounded recovery", () => {
  it("stops as soon as the answer is conclusive", async () => {
    let calls = 0;
    const r = await boundedPoll(async () => { calls++; return "ok"; }, { attempts: 5, baseMs: 1 });
    expect(calls).toBe(1);
    expect(r.done).toBe(true);
  });

  it("never loops beyond its attempt budget", async () => {
    let calls = 0;
    const r = await boundedPoll(async () => { calls++; throw new Error("Failed to fetch"); }, {
      attempts: 3, baseMs: 1, maxMs: 2,
    });
    expect(calls).toBe(3);
    expect(r.done).toBe(false);
    expect(r.exhausted).toBe(true);
  });

  it("resolves rather than rejecting, so the UI can stay honest", async () => {
    await expect(boundedPoll(async () => { throw new Error("boom"); }, { attempts: 1 })).resolves.toBeTruthy();
  });

  it("backoff grows but stays clamped", () => {
    for (let a = 1; a <= 8; a++) {
      const d = backoffDelayMs(a, 500, 4000);
      expect(d).toBeGreaterThan(0);
      expect(d).toBeLessThanOrEqual(4000);
    }
  });

  it("treats lost connections as recoverable and refusals as final", () => {
    expect(isLostResponseError(new Error("Failed to fetch"))).toBe(true);
    expect(isLostResponseError(new Error("network timeout"))).toBe(true);
    expect(isLostResponseError(new Error("Stock insuffisant pour cette quantité."))).toBe(false);
  });
});

describe("R13 — offline basket draft has no economic authority", () => {
  beforeEach(() => { clearBasketDraft(); });

  it("persists and restores an offline-composed draft", () => {
    saveBasketDraft({
      storeId: "s1",
      lines: [{ listingId: "l1", qty: 2, cachedUnitPriceGnf: 10000 }],
      destination: { landmark: "près du marché Madina" },
      updatedAt: Date.now(),
    });
    const back = loadBasketDraft();
    expect(back?.lines[0].qty).toBe(2);
    expect(back?.destination.landmark).toBe("près du marché Madina");
  });

  it("keeps a cached price as drift evidence only, never a total", () => {
    const d = normalizeDraft({
      storeId: "s1",
      lines: [{ listingId: "l1", qty: 1, cachedUnitPriceGnf: 9000 }],
      destination: {},
    });
    expect(d).toBeTruthy();
    expect(Object.keys(d as object)).not.toContain("merchandise_subtotal_gnf");
    expect(Object.keys(d as object)).not.toContain("total_gnf");
  });

  it("clamps hostile quantities and drops duplicate lines", () => {
    const d = normalizeDraft({
      storeId: "s1",
      lines: [
        { listingId: "l1", qty: 99999 },
        { listingId: "l1", qty: 3 },
        { listingId: "l2", qty: -4 },
      ],
      destination: {},
    });
    expect(d?.lines).toHaveLength(2);
    expect(d?.lines[0].qty).toBe(100);
    expect(d?.lines[1].qty).toBe(1);
  });

  it("rejects a storeless draft", () => {
    expect(normalizeDraft({ lines: [{ listingId: "l1", qty: 1 }] })).toBeNull();
  });

  it("accepts a landmark alone as a usable Conakry destination", () => {
    expect(hasUsableDestination({ landmark: "derrière la mosquée" })).toBe(true);
    expect(hasUsableDestination({})).toBe(false);
  });

  it("never stores a location verdict — that is the server's word", () => {
    const d = normalizeDraft({
      storeId: "s1",
      lines: [{ listingId: "l1", qty: 1 }],
      destination: { landmark: "Madina", source: "gps" },
    });
    expect(JSON.stringify(d)).not.toContain("gps_verified");
  });
});

describe("R13 — commitment identity survives the upgrade", () => {
  beforeEach(() => { localStorage.clear(); });

  it("a landmark-free intent keeps its pre-R13 fingerprint", () => {
    const legacy = orderIntentKey({ storeId: "s1", lines: [{ listingId: "l1", qty: 1 }], deliveryAddress: "Kaloum" });
    expect(legacy).toBe("s1|l1:1:|Kaloum||");
  });

  it("a landmark changes the intent, so a new key is issued", () => {
    const a = orderIntentKey({ storeId: "s1", lines: [{ listingId: "l1", qty: 1 }] });
    const b = orderIntentKey({ storeId: "s1", lines: [{ listingId: "l1", qty: 1 }], destinationLandmark: "Madina" });
    expect(a).not.toBe(b);
  });

  it("repeated taps on the same basket reuse one durable key", () => {
    const store = createOrderRequestIdStore("t13");
    const intent = { storeId: "s1", lines: [{ listingId: "l1", qty: 1 }], destinationLandmark: "Madina" };
    const ids = new Set(Array.from({ length: 10 }, () => store.idFor(intent)));
    expect(ids.size).toBe(1);
  });

  it("the key survives a reload", () => {
    const intent = { storeId: "s1", lines: [{ listingId: "l1", qty: 1 }] };
    const first = createOrderRequestIdStore("t13").idFor(intent);
    expect(createOrderRequestIdStore("t13").idFor(intent)).toBe(first);
  });
});

describe("R13 — honest French for server refusals and verdicts", () => {
  it("translates the R13 refusals", () => {
    expect(translateOrderError("LISTING_QUARANTINED")).toMatch(/suspendu/i);
    expect(translateOrderError("STORE_SUSPENDED")).toMatch(/suspendue/i);
    expect(translateOrderError("CLIENT_LOCATION_QUALITY_NOT_ALLOWED")).toMatch(/CHOP CHOP/);
  });

  it("never claims GPS when the server said otherwise", () => {
    expect(destinationQualityLabel("landmark_assisted")).not.toMatch(/GPS confirm/i);
    expect(destinationQualityLabel("gps_verified")).toMatch(/GPS/);
    expect(destinationQualityLabel(null)).toMatch(/non vérifiable/i);
  });
});
