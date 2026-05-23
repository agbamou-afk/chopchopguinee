/**
 * CHOPCHOP Sandbox Operational Testing — type contracts.
 *
 * Everything here is INTERNAL, IN-MEMORY, and ISOLATED from production
 * runtime. No types defined in this module should leak into live
 * dispatch, real wallet, or live presence code paths.
 */

type DistrictKey = string;

export type SyntheticActorKind =
  | "rider"
  | "customer"
  | "courier"
  | "restaurant"
  | "seller";

export interface SyntheticActor {
  id: string;
  kind: SyntheticActorKind;
  label: string;
  district?: DistrictKey;
  /** Free-form deterministic state bag the engine writes to. */
  state: Record<string, string | number | boolean | null>;
  createdAt: number;
}

export type SyntheticMissionKind =
  | "moto"
  | "repas"
  | "marche"
  | "envoyer";

export type SyntheticMissionState =
  | "pending"
  | "dispatched"
  | "accepted"
  | "en_route"
  | "arrived"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "failed"
  | "timeout";

export interface SyntheticMission {
  id: string;
  kind: SyntheticMissionKind;
  state: SyntheticMissionState;
  pickupDistrict?: DistrictKey;
  dropoffDistrict?: DistrictKey;
  actorIds: string[];
  scenarioId?: string;
  /** Monetary continuity (sandbox-only, no real wallet). */
  amountGnf: number;
  startedAt: number;
  updatedAt: number;
  failureReason?: string;
}

export type SandboxEventLevel = "info" | "warn" | "error" | "success";

export interface SandboxEvent {
  id: string;
  ts: number;
  level: SandboxEventLevel;
  scope:
    | "actor"
    | "mission"
    | "wallet"
    | "notification"
    | "scenario"
    | "system";
  message: string;
  refId?: string;
}

export interface SandboxWalletEntry {
  id: string;
  ts: number;
  actorId: string;
  missionId?: string;
  kind: "receipt" | "earning" | "merchant_inflow" | "refund" | "hold";
  amountGnf: number;
  note?: string;
}

export interface SandboxScenarioContext {
  spawnActor: (
    kind: SyntheticActorKind,
    overrides?: Partial<Omit<SyntheticActor, "id" | "kind" | "createdAt" | "state">> & {
      state?: SyntheticActor["state"];
    },
  ) => SyntheticActor;
  spawnMission: (mission: Omit<SyntheticMission, "id" | "startedAt" | "updatedAt" | "state"> & {
    state?: SyntheticMissionState;
  }) => SyntheticMission;
  transitionMission: (
    missionId: string,
    next: SyntheticMissionState,
    opts?: { reason?: string },
  ) => void;
  walletEntry: (entry: Omit<SandboxWalletEntry, "id" | "ts">) => void;
  notify: (message: string, opts?: { level?: SandboxEventLevel; refId?: string }) => void;
  log: (message: string, opts?: { level?: SandboxEventLevel; scope?: SandboxEvent["scope"]; refId?: string }) => void;
  /** Resolves after the given ms in scenario time. */
  wait: (ms: number) => Promise<void>;
}

export interface SandboxScenario {
  id: string;
  title: string;
  description: string;
  /** Family used for filtering in the control panel. */
  family: "ride" | "repas" | "marche" | "wallet" | "failure" | "notification" | "merchant";
  run: (ctx: SandboxScenarioContext) => Promise<void> | void;
  /**
   * Optional declarative expectations evaluated after the scenario runs.
   * Used to compute a health score (pass / warn / fail) — purely in-memory.
   */
  expected?: SandboxScenarioExpectations;
}

export interface SandboxSnapshot {
  actors: SyntheticActor[];
  missions: SyntheticMission[];
  events: SandboxEvent[];
  wallet: SandboxWalletEntry[];
  runningScenarios: string[];
  runs: SandboxScenarioRun[];
}

export type SandboxRunStatus = "running" | "completed" | "failed" | "cancelled";

export type SandboxHealth = "pass" | "warn" | "fail";

export interface SandboxScenarioExpectations {
  /** Exact number of missions spawned. */
  missions?: number;
  /** Exact number of missions reaching `completed`. */
  completed?: number;
  /** Exact number of missions ending in failed/cancelled/timeout. */
  failed?: number;
  /** Exact number of wallet entries emitted. */
  wallet?: number;
  /** Exact number of notifications emitted. */
  notifications?: number;
  /** Max allowed identical notification message (dedupe threshold). */
  maxDuplicateNotifications?: number;
  /** Max allowed non-terminal missions at end of scenario. */
  maxUnresolvedMissions?: number;
  /** Every spawned mission must carry pickup AND dropoff district. */
  requireDistrictContinuity?: boolean;
  /** All listed failure reasons must appear at least once. */
  failureReasons?: string[];
  /** When true, scenario is allowed to end with warn status (no fail demotion). */
  warnTolerant?: boolean;
  /** Human label explaining why unresolved missions are acceptable (e.g. "expected backlog"). */
  pendingLabel?: string;
}

export interface SandboxAssertion {
  label: string;
  ok: boolean;
  severity: "warn" | "fail";
  detail?: string;
}

export interface SandboxScenarioRun {
  id: string;
  scenarioId: string;
  title: string;
  status: SandboxRunStatus;
  startedAt: number;
  endedAt?: number;
  durationMs?: number;
  counts: {
    actors: number;
    missions: number;
    wallet: number;
    notifications: number;
    failures: number;
  };
  error?: string;
  /** Aggregate health verdict (filled after run ends). */
  health?: SandboxHealth;
  /** Per-rule assertion results. */
  assertions?: SandboxAssertion[];
  /** Human-readable warnings & failure summaries. */
  warnings?: string[];
  /** Mission ids spawned during this run. */
  missionIds?: string[];
  /** Notification messages emitted during this run (raw, pre-dedupe). */
  notificationMessages?: string[];
  /** Failure reasons observed via transitionMission. */
  failureReasons?: string[];
  /** Count of notifications that collapsed into a prior event row. */
  dedupedNotifications?: number;
  /** Optional contextual note (e.g. "expected backlog: 3 pending"). */
  note?: string;
}