/**
 * FINAL FEATURE-EXPOSURE LIVE-PROPAGATION CLOSEOUT.
 * Proves God-Admin flag toggles propagate into already-open customer UIs
 * through the SINGLE existing feature-flag store.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const rows: { key: string; enabled: boolean }[] = [];
let selectCalls = 0;

const channelHandlers: { cb?: (p: unknown) => void; status?: (s: string) => void }[] = [];
const createdChannels: string[] = [];
const removed: unknown[] = [];

vi.mock("@/integrations/supabase/client", () => {
  const channel = (name: string) => {
    createdChannels.push(name);
    const entry: { cb?: (p: unknown) => void; status?: (s: string) => void } = {};
    channelHandlers.push(entry);
    const api = {
      on: (_evt: string, _filter: unknown, cb: (p: unknown) => void) => { entry.cb = cb; return api; },
      subscribe: (statusCb?: (s: string) => void) => { entry.status = statusCb; return api; },
    };
    return api;
  };
  return {
    supabase: {
      from: () => ({
        select: () => ({
          in: async () => { selectCalls += 1; return { data: [...rows], error: null }; },
        }),
      }),
      channel,
      removeChannel: (c: unknown) => { removed.push(c); },
    },
  };
});

import {
  loadFeatureFlags,
  refreshFeatureFlags,
  getFlag,
  subscribeFlags,
  applyFlagRealtimeEvent,
  handleFlagChannelStatus,
  initFeatureFlagsRealtime,
  teardownFeatureFlagsRealtime,
  __flagsRealtimeActiveForTests,
  __resetFeatureFlagsForTests,
  CLIENT_FLAG_DEFAULTS,
} from "@/lib/flags/featureFlags";

beforeEach(() => {
  rows.length = 0;
  selectCalls = 0;
  channelHandlers.length = 0;
  createdChannels.length = 0;
  removed.length = 0;
  teardownFeatureFlagsRealtime();
  __resetFeatureFlagsForTests({}, false);
});

afterEach(() => { teardownFeatureFlagsRealtime(); });

describe("feature flags — initial load (unchanged law)", () => {
  it("hydrates the shared cache from the DB rows once", async () => {
    rows.push({ key: "taxi", enabled: false }, { key: "service_repas_enabled", enabled: true });
    await loadFeatureFlags();
    await loadFeatureFlags();
    expect(selectCalls).toBe(1);
    expect(getFlag("taxi")).toBe(false);
    expect(getFlag("service_repas_enabled")).toBe(true);
  });
});

describe("realtime propagation into the shared store", () => {
  it("UPDATE taxi false -> true updates cache and notifies subscribers", async () => {
    rows.push({ key: "taxi", enabled: false });
    await loadFeatureFlags();
    const seen: boolean[] = [];
    const off = subscribeFlags(() => seen.push(getFlag("taxi")));
    applyFlagRealtimeEvent({ eventType: "UPDATE", new: { key: "taxi", enabled: true } });
    off();
    expect(getFlag("taxi")).toBe(true);
    expect(seen).toEqual([true]);
  });

  it("UPDATE service_repas_enabled true -> false applies immediately", async () => {
    rows.push({ key: "service_repas_enabled", enabled: true });
    await loadFeatureFlags();
    applyFlagRealtimeEvent({ eventType: "UPDATE", new: { key: "service_repas_enabled", enabled: false } });
    expect(getFlag("service_repas_enabled")).toBe(false);
  });

  it("DELETE of a known flag reverts to the compiled DEFAULT, not stale truth", async () => {
    rows.push({ key: "taxi", enabled: true });
    await loadFeatureFlags();
    expect(getFlag("taxi")).toBe(true);
    applyFlagRealtimeEvent({ eventType: "DELETE", old: { key: "taxi", enabled: true } });
    expect(getFlag("taxi")).toBe(CLIENT_FLAG_DEFAULTS.taxi);
  });

  it("ignores unknown flag keys entirely", async () => {
    await loadFeatureFlags();
    const changed = applyFlagRealtimeEvent({ eventType: "UPDATE", new: { key: "not_a_client_flag", enabled: true } });
    expect(changed).toBe(false);
    expect((getFlag as unknown as (k: string) => boolean)("not_a_client_flag")).toBeUndefined();
  });

  it("does not emit when the value is unchanged", async () => {
    rows.push({ key: "taxi", enabled: false });
    await loadFeatureFlags();
    let emits = 0;
    const off = subscribeFlags(() => { emits += 1; });
    applyFlagRealtimeEvent({ eventType: "UPDATE", new: { key: "taxi", enabled: false } });
    off();
    expect(emits).toBe(0);
  });

  it("routes the live channel payload through the same applier", async () => {
    rows.push({ key: "service_marche_enabled", enabled: true });
    await loadFeatureFlags();
    initFeatureFlagsRealtime();
    channelHandlers[0].cb?.({ eventType: "UPDATE", new: { key: "service_marche_enabled", enabled: false } });
    expect(getFlag("service_marche_enabled")).toBe(false);
  });
});

describe("subscription lifecycle", () => {
  it("duplicate initialization creates only one effective subscription", () => {
    initFeatureFlagsRealtime();
    initFeatureFlagsRealtime();
    initFeatureFlagsRealtime();
    expect(createdChannels).toEqual(["feature-flags-live"]);
    expect(__flagsRealtimeActiveForTests()).toBe(true);
  });

  it("teardown releases the channel and allows a later re-init", () => {
    initFeatureFlagsRealtime();
    teardownFeatureFlagsRealtime();
    expect(__flagsRealtimeActiveForTests()).toBe(false);
    expect(removed.length).toBe(1);
    initFeatureFlagsRealtime();
    expect(createdChannels.length).toBe(2);
  });

  it("realtime loss keeps cached truth and does not refetch", async () => {
    rows.push({ key: "taxi", enabled: true });
    await loadFeatureFlags();
    selectCalls = 0;
    handleFlagChannelStatus("CHANNEL_ERROR");
    expect(getFlag("taxi")).toBe(true);
    expect(selectCalls).toBe(0);
  });

  it("reconnect after a drop triggers a full refresh/reconciliation", async () => {
    rows.push({ key: "taxi", enabled: false });
    await loadFeatureFlags();
    selectCalls = 0;
    handleFlagChannelStatus("CHANNEL_ERROR");
    rows.length = 0;
    rows.push({ key: "taxi", enabled: true });
    handleFlagChannelStatus("SUBSCRIBED");
    await new Promise((r) => setTimeout(r, 0));
    expect(selectCalls).toBe(1);
    expect(getFlag("taxi")).toBe(true);
  });

  it("first SUBSCRIBED (no prior drop) does not refetch", async () => {
    await loadFeatureFlags();
    selectCalls = 0;
    handleFlagChannelStatus("SUBSCRIBED");
    await new Promise((r) => setTimeout(r, 0));
    expect(selectCalls).toBe(0);
  });
});

describe("admin refresh path", () => {
  it("refreshFeatureFlags re-reads the DB into the shared cache", async () => {
    rows.push({ key: "taxi", enabled: false });
    await loadFeatureFlags();
    rows.length = 0;
    rows.push({ key: "taxi", enabled: true });
    await refreshFeatureFlags();
    expect(getFlag("taxi")).toBe(true);
    expect(selectCalls).toBe(2);
  });
});
