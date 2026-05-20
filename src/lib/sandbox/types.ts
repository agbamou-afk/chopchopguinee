/**
 * CHOP Sandbox Operational Testing — type contracts.
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
}

export interface SandboxSnapshot {
  actors: SyntheticActor[];
  missions: SyntheticMission[];
  events: SandboxEvent[];
  wallet: SandboxWalletEntry[];
  runningScenarios: string[];
}