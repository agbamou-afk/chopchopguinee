/**
 * CHOPCHOP Sandbox Engine — deterministic in-memory operational simulator.
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
  SandboxAssertion,
  SandboxEvent,
  SandboxEventLevel,
  SandboxHealth,
  SandboxScenario,
  SandboxScenarioContext,
  SandboxScenarioExpectations,
  SandboxScenarioRun,
  SandboxSnapshot,
  SandboxWalletEntry,
  SyntheticActor,
  SyntheticActorKind,
  SyntheticMission,
  SyntheticMissionState,
} from "./types";

const MAX_EVENTS = 200;
const MAX_WALLET = 200;
const MAX_RUNS = 40;
const NOTIFY_DEDUPE_MS = 2000;

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
  private runs: SandboxScenarioRun[] = [];
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
      runs: [...this.runs],
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

  /**
   * Emit an operational notification. Collapses identical consecutive
   * messages emitted within {@link NOTIFY_DEDUPE_MS} into a single event
   * row with an `×N` suffix — matches the dedupe behaviour we want in
   * live notification surfaces.
   *
   * Returns `true` when the call collapsed into an existing event.
   */
  notify(message: string, opts?: { level?: SandboxEventLevel; refId?: string }): boolean {
    const base = `🔔 ${message}`;
    const last = this.events[0];
    if (last && last.scope === "notification" && Date.now() - last.ts < NOTIFY_DEDUPE_MS) {
      const stripped = last.message.replace(/ ×\d+$/, "");
      if (stripped === base) {
        const m = last.message.match(/ ×(\d+)$/);
        const n = m ? parseInt(m[1], 10) + 1 : 2;
        last.message = `${stripped} ×${n}`;
        last.ts = Date.now();
        this.emit();
        return true;
      }
    }
    this.log(base, { scope: "notification", level: opts?.level, refId: opts?.refId });
    return false;
  }

  clear() {
    this.actors.clear();
    this.missions.clear();
    this.events = [];
    this.wallet = [];
    this.running.clear();
    this.runs = [];
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
    const run: SandboxScenarioRun = {
      id: rid("run"),
      scenarioId: scenario.id,
      title: scenario.title,
      status: "running",
      startedAt: Date.now(),
      counts: { actors: 0, missions: 0, wallet: 0, notifications: 0, failures: 0 },
      missionIds: [],
      notificationMessages: [],
      failureReasons: [],
    };
    this.runs.unshift(run);
    if (this.runs.length > MAX_RUNS) this.runs.length = MAX_RUNS;
    this.emit();
    this.log(`▶ Scenario start: ${scenario.title}`, { scope: "scenario", refId: scenario.id });

    const ctx: SandboxScenarioContext = {
      spawnActor: (kind, overrides) => {
        const a = this.spawnActor(kind, overrides);
        run.counts.actors += 1;
        return a;
      },
      spawnMission: (m) => {
        const mission = this.spawnMission({ ...m, scenarioId: scenario.id });
        run.counts.missions += 1;
        run.missionIds!.push(mission.id);
        return mission;
      },
      transitionMission: (id, next, o) => {
        this.transitionMission(id, next, o);
        if (next === "failed" || next === "timeout" || next === "cancelled") {
          run.counts.failures += 1;
          if (o?.reason) run.failureReasons!.push(o.reason);
        }
      },
      walletEntry: (e) => {
        this.walletEntry(e);
        run.counts.wallet += 1;
      },
      notify: (msg, o) => {
        const deduped = this.notify(msg, o);
        if (!deduped) {
          run.counts.notifications += 1;
          run.notificationMessages!.push(msg);
        } else {
          run.dedupedNotifications = (run.dedupedNotifications ?? 0) + 1;
        }
      },
      log: (msg, o) => this.log(msg, o),
      wait: (ms) => new Promise((r) => setTimeout(r, ms)),
    };

    try {
      await scenario.run(ctx);
      run.status = "completed";
      this.log(`✓ Scenario done: ${scenario.title}`, { scope: "scenario", level: "success", refId: scenario.id });
    } catch (err) {
      run.status = "failed";
      run.error = (err as Error)?.message ?? String(err);
      this.log(`✗ Scenario failed: ${scenario.title} — ${run.error}`, {
        scope: "scenario",
        level: "error",
        refId: scenario.id,
      });
    } finally {
      run.endedAt = Date.now();
      run.durationMs = run.endedAt - run.startedAt;
      this.evaluateHealth(run, scenario.expected);
      this.running.delete(scenario.id);
      this.emit();
    }
  }

  private evaluateHealth(run: SandboxScenarioRun, expected?: SandboxScenarioExpectations) {
    const assertions: SandboxAssertion[] = [];
    const warnings: string[] = [];

    if (run.status === "failed") {
      run.health = "fail";
      run.assertions = [{ label: "scenario executed", ok: false, severity: "fail", detail: run.error }];
      run.warnings = [run.error ?? "scenario threw"];
      return;
    }

    // Terminal vs unresolved missions from authoritative engine state.
    const TERMINAL: SyntheticMissionState[] = ["completed", "cancelled", "failed", "timeout"];
    const missions = (run.missionIds ?? [])
      .map((id) => this.missions.get(id))
      .filter((m): m is SyntheticMission => !!m);
    const completed = missions.filter((m) => m.state === "completed").length;
    const failedLike = missions.filter((m) => m.state === "failed" || m.state === "cancelled" || m.state === "timeout").length;
    const unresolved = missions.filter((m) => !TERMINAL.includes(m.state)).length;

    const exp = expected ?? {};
    const check = (label: string, ok: boolean, severity: "warn" | "fail", detail?: string) => {
      assertions.push({ label, ok, severity, detail });
      if (!ok) warnings.push(`${severity === "fail" ? "✗" : "⚠"} ${label}${detail ? ` — ${detail}` : ""}`);
    };

    if (exp.missions != null) {
      check(`missions = ${exp.missions}`, run.counts.missions === exp.missions, "fail",
        `got ${run.counts.missions}`);
    }
    if (exp.completed != null) {
      check(`completed = ${exp.completed}`, completed === exp.completed, "fail", `got ${completed}`);
    }
    if (exp.failed != null) {
      check(`failed = ${exp.failed}`, failedLike === exp.failed, "warn", `got ${failedLike}`);
    }
    if (exp.wallet != null) {
      check(`wallet entries = ${exp.wallet}`, run.counts.wallet === exp.wallet, "warn",
        `got ${run.counts.wallet}`);
    }
    if (exp.notifications != null) {
      check(`notifications = ${exp.notifications}`, run.counts.notifications === exp.notifications, "warn",
        `got ${run.counts.notifications}`);
    }

    if (exp.maxDuplicateNotifications != null) {
      const counts = new Map<string, number>();
      (run.notificationMessages ?? []).forEach((m) => counts.set(m, (counts.get(m) ?? 0) + 1));
      const worst = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
      const worstCount = worst?.[1] ?? 0;
      check(
        `duplicate notifs ≤ ${exp.maxDuplicateNotifications}`,
        worstCount <= exp.maxDuplicateNotifications,
        "warn",
        worst ? `"${worst[0]}" × ${worstCount}` : undefined,
      );
    }

    if (exp.maxUnresolvedMissions != null) {
      const ok = unresolved <= exp.maxUnresolvedMissions;
      const label = exp.pendingLabel
        ? `${exp.pendingLabel} (≤ ${exp.maxUnresolvedMissions})`
        : `unresolved missions ≤ ${exp.maxUnresolvedMissions}`;
      check(label, ok, "fail", ok ? (unresolved > 0 ? `${unresolved} pending — intentional` : undefined) : `got ${unresolved}`);
      if (ok && unresolved > 0 && exp.pendingLabel) {
        run.note = `${exp.pendingLabel}: ${unresolved} pending`;
      }
    } else if (unresolved > 0) {
      // Default sanity check: a clean run should not leave stuck missions.
      const stuckStates = [...new Set(missions.filter((m) => !TERMINAL.includes(m.state)).map((m) => m.state))].join(", ");
      check("no stuck missions", false, "fail",
        `${unresolved} non-terminal (${stuckStates}) — add terminal transition or set maxUnresolvedMissions`);
    }

    if (exp.requireDistrictContinuity) {
      const missingPair = missions.filter((m) => !m.pickupDistrict || !m.dropoffDistrict).length;
      check("district continuity", missingPair === 0, "warn",
        missingPair ? `${missingPair} missions missing pickup/dropoff` : undefined);
    }

    if (exp.failureReasons && exp.failureReasons.length > 0) {
      const observed = new Set(run.failureReasons ?? []);
      const missing = exp.failureReasons.filter((r) => !observed.has(r));
      check(`failure reasons: ${exp.failureReasons.join(", ")}`, missing.length === 0, "fail",
        missing.length ? `missing ${missing.join(", ")}` : undefined);
    }

    if ((run.dedupedNotifications ?? 0) > 0) {
      assertions.push({
        label: `notifications deduped × ${run.dedupedNotifications}`,
        ok: true,
        severity: "warn",
        detail: "consecutive duplicates collapsed",
      });
    }

    let health: SandboxHealth = "pass";
    for (const a of assertions) {
      if (!a.ok) {
        if (a.severity === "fail") { health = "fail"; break; }
        health = "warn";
      }
    }
    if (health === "fail" && exp.warnTolerant) health = "warn";

    run.assertions = assertions;
    run.warnings = warnings;
    run.health = health;
  }
}

export const sandboxEngine = new SandboxEngine();