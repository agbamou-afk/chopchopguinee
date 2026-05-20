/**
 * CHOP Sandbox Engine — deterministic in-memory operational simulator.
 *
 * Hard rules:
 *   - Pure client-side. No Supabase writes. No realtime channels.
 *   - No mutation of live wallets, presence, dispatch, or ride tables.
 *   - Only mounts inside sandbox runtime (?sandbox=1 / ?debug=1 / DEV).
 *
 * The engine exposes a tiny pub/sub store consumed by the
 * SandboxOpsPanel devtool. Scenarios push synthetic actors, missions,
 * wallet entries, and events through the engine; nothing else in the
 * app observes this module.
 */

import { isSandboxMode } from "@/lib/runtimeMode";
import type {
  SandboxEvent,
  SandboxEventLevel,
  SandboxScenario,
  SandboxScenarioContext,
  SandboxSnapshot,
  SandboxWalletEntry,
  SyntheticActor,
  SyntheticActorKind,
  SyntheticMission,
  SyntheticMissionState,
} from "./types";

const MAX_EVENTS = 200;
const MAX_WALLET = 200;

function rid(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 8)}${Date.now().toString(36).slice(-3)}`;
}

type Listener = (snap: SandboxSnapshot) => void;

class SandboxEngine {
  private actors = new Map<string, SyntheticActor>();
  private missions = new Map<string, SyntheticMission>();
  private events: SandboxEvent[] = [];
  private wallet: SandboxWalletEntry[] = [];
  private running = new Set<string>();
  private listeners = new Set<Listener>();

  enabled(): boolean {
    return isSandboxMode();
  }

  snapshot(): SandboxSnapshot {
    return {
      actors: [...this.actors.values()].sort((a, b) => b.createdAt - a.createdAt),
      missions: [...this.missions.values()].sort((a, b) => b.updatedAt - a.updatedAt),
      events: [...this.events],
      wallet: [...this.wallet],
      runningScenarios: [...this.running],
    };
  }

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    fn(this.snapshot());
    return () => { this.listeners.delete(fn); };
  }

  private emit() {
    const snap = this.snapshot();
    this.listeners.forEach((l) => { try { l(snap); } catch { /* noop */ } });
  }

  log(message: string, opts?: { level?: SandboxEventLevel; scope?: SandboxEvent["scope"]; refId?: string }) {
    const evt: SandboxEvent = {
      id: rid("evt"),
      ts: Date.now(),
      level: opts?.level ?? "info",
      scope: opts?.scope ?? "system",
      message,
      refId: opts?.refId,
    };
    this.events.unshift(evt);
    if (this.events.length > MAX_EVENTS) this.events.length = MAX_EVENTS;
    this.emit();
  }

  spawnActor(
    kind: SyntheticActorKind,
    overrides?: Partial<Omit<SyntheticActor, "id" | "kind" | "createdAt" | "state">> & {
      state?: SyntheticActor["state"];
    },
  ): SyntheticActor {
    const id = rid(`act_${kind}`);
    const actor: SyntheticActor = {
      id,
      kind,
      label: overrides?.label ?? `${kind}-${id.slice(-4)}`,
      district: overrides?.district,
      state: overrides?.state ?? {},
      createdAt: Date.now(),
    };
    this.actors.set(id, actor);
    this.log(`Actor spawn: ${actor.label}`, { scope: "actor", refId: id });
    return actor;
  }

  spawnMission(input: Omit<SyntheticMission, "id" | "startedAt" | "updatedAt" | "state"> & {
    state?: SyntheticMissionState;
  }): SyntheticMission {
    const id = rid(`mis_${input.kind}`);
    const now = Date.now();
    const mission: SyntheticMission = {
      id,
      kind: input.kind,
      state: input.state ?? "pending",
      pickupDistrict: input.pickupDistrict,
      dropoffDistrict: input.dropoffDistrict,
      actorIds: input.actorIds,
      scenarioId: input.scenarioId,
      amountGnf: input.amountGnf,
      startedAt: now,
      updatedAt: now,
    };
    this.missions.set(id, mission);
    this.log(`Mission spawn ${input.kind} (${mission.state})`, { scope: "mission", refId: id });
    return mission;
  }

  transitionMission(missionId: string, next: SyntheticMissionState, opts?: { reason?: string }) {
    const m = this.missions.get(missionId);
    if (!m) return;
    const prev = m.state;
    m.state = next;
    m.updatedAt = Date.now();
    if (opts?.reason) m.failureReason = opts.reason;
    const failure = next === "failed" || next === "timeout" || next === "cancelled";
    this.log(`${m.kind} ${prev} → ${next}${opts?.reason ? ` (${opts.reason})` : ""}`, {
      scope: "mission",
      level: failure ? "warn" : next === "completed" ? "success" : "info",
      refId: missionId,
    });
  }

  walletEntry(entry: Omit<SandboxWalletEntry, "id" | "ts">) {
    const row: SandboxWalletEntry = { id: rid("wal"), ts: Date.now(), ...entry };
    this.wallet.unshift(row);
    if (this.wallet.length > MAX_WALLET) this.wallet.length = MAX_WALLET;
    this.log(`Wallet ${entry.kind}: ${entry.amountGnf.toLocaleString("fr-FR")} GNF`, {
      scope: "wallet",
      refId: entry.missionId ?? entry.actorId,
    });
  }

  notify(message: string, opts?: { level?: SandboxEventLevel; refId?: string }) {
    this.log(`🔔 ${message}`, { scope: "notification", level: opts?.level, refId: opts?.refId });
  }

  clear() {
    this.actors.clear();
    this.missions.clear();
    this.events = [];
    this.wallet = [];
    this.running.clear();
    this.emit();
  }

  async runScenario(scenario: SandboxScenario): Promise<void> {
    if (!this.enabled()) {
      this.log(`Refused scenario "${scenario.id}" — sandbox disabled`, { level: "error" });
      return;
    }
    if (this.running.has(scenario.id)) {
      this.log(`Scenario "${scenario.id}" already running`, { level: "warn", scope: "scenario" });
      return;
    }
    this.running.add(scenario.id);
    this.emit();
    this.log(`▶ Scenario start: ${scenario.title}`, { scope: "scenario", refId: scenario.id });

    const ctx: SandboxScenarioContext = {
      spawnActor: (kind, overrides) => this.spawnActor(kind, overrides),
      spawnMission: (m) => this.spawnMission({ ...m, scenarioId: scenario.id }),
      transitionMission: (id, next, o) => this.transitionMission(id, next, o),
      walletEntry: (e) => this.walletEntry(e),
      notify: (msg, o) => this.notify(msg, o),
      log: (msg, o) => this.log(msg, o),
      wait: (ms) => new Promise((r) => setTimeout(r, ms)),
    };

    try {
      await scenario.run(ctx);
      this.log(`✓ Scenario done: ${scenario.title}`, { scope: "scenario", level: "success", refId: scenario.id });
    } catch (err) {
      this.log(`✗ Scenario failed: ${scenario.title} — ${(err as Error)?.message ?? err}`, {
        scope: "scenario",
        level: "error",
        refId: scenario.id,
      });
    } finally {
      this.running.delete(scenario.id);
      this.emit();
    }
  }
}

export const sandboxEngine = new SandboxEngine();