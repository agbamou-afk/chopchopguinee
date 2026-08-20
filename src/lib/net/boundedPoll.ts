/**
 * Node 4 — Marché R13: bounded retry / poll helper for weak Conakry networks.
 *
 * Conakry mobile data drops mid-request constantly. The honest recovery for a
 * lost RESPONSE is never "send the mutation again", it is "ask the server what
 * it actually recorded". This helper exists so those read-side recoveries are
 * always BOUNDED: a fixed attempt budget, exponential backoff with jitter, an
 * absolute deadline and cooperative abort. It never loops forever, never
 * hammers a degraded network, and carries no economic authority of its own.
 */

export interface BoundedPollOptions<T> {
  /** Hard cap on attempts, including the first one. */
  attempts?: number;
  /** First backoff delay in ms. */
  baseMs?: number;
  /** Upper bound for a single backoff delay. */
  maxMs?: number;
  /** Absolute wall-clock budget for the whole poll. */
  deadlineMs?: number;
  /** Return true when the value is conclusive and polling must stop. */
  isDone?: (value: T) => boolean;
  /** Cooperative cancellation (component unmount, sheet closed). */
  signal?: AbortSignal;
  /** Observability hook; never throws. */
  onAttempt?: (attempt: number, error: unknown) => void;
}

export interface BoundedPollResult<T> {
  /** Last successful value, or null when every attempt failed. */
  value: T | null;
  /** True when `isDone` accepted the value. */
  done: boolean;
  attempts: number;
  /** Last error seen, when the poll never produced a conclusive value. */
  error: unknown;
  /** True when the attempt budget or the deadline ran out. */
  exhausted: boolean;
}

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve) => {
    if (ms <= 0) return resolve();
    const t = setTimeout(resolve, ms);
    signal?.addEventListener(
      "abort",
      () => {
        clearTimeout(t);
        resolve();
      },
      { once: true },
    );
  });

/** Backoff with full jitter, clamped to `maxMs`. Exported for tests. */
export function backoffDelayMs(attempt: number, baseMs: number, maxMs: number): number {
  const ideal = Math.min(maxMs, baseMs * Math.pow(2, Math.max(0, attempt - 1)));
  return Math.round(ideal / 2 + Math.random() * (ideal / 2));
}

/**
 * Runs `fn` until it returns a conclusive value, the attempt budget is spent,
 * the deadline passes or the caller aborts. Always resolves — never rejects —
 * so callers can render an honest "nous n'avons pas pu confirmer" state instead
 * of guessing.
 */
export async function boundedPoll<T>(
  fn: (attempt: number) => Promise<T>,
  opts: BoundedPollOptions<T> = {},
): Promise<BoundedPollResult<T>> {
  const attempts = Math.max(1, Math.min(opts.attempts ?? 4, 10));
  const baseMs = Math.max(50, opts.baseMs ?? 600);
  const maxMs = Math.max(baseMs, opts.maxMs ?? 6000);
  const deadline = Date.now() + Math.max(1000, opts.deadlineMs ?? 20000);
  const isDone = opts.isDone ?? ((v: T) => v != null);

  let value: T | null = null;
  let error: unknown = null;
  let used = 0;

  for (let attempt = 1; attempt <= attempts; attempt++) {
    if (opts.signal?.aborted) break;
    if (Date.now() > deadline) return { value, done: false, attempts: used, error, exhausted: true };
    used = attempt;
    try {
      const out = await fn(attempt);
      value = out;
      error = null;
      if (isDone(out)) return { value: out, done: true, attempts: used, error: null, exhausted: false };
    } catch (e) {
      error = e;
    }
    try {
      opts.onAttempt?.(attempt, error);
    } catch {
      /* observability must never break recovery */
    }
    if (attempt < attempts) await sleep(backoffDelayMs(attempt, baseMs, maxMs), opts.signal);
  }

  return { value, done: false, attempts: used, error, exhausted: true };
}

/**
 * Heuristic for "the request may have reached the server but the answer was
 * lost". Only these deserve a read-side recovery attempt; a server refusal
 * (a translated business error) is a definitive answer and must be shown.
 */
export function isLostResponseError(e: unknown): boolean {
  const msg = (e instanceof Error ? e.message : String(e ?? "")).toLowerCase();
  if (!msg) return true;
  return (
    msg.includes("failed to fetch") ||
    msg.includes("network") ||
    msg.includes("networkerror") ||
    msg.includes("timeout") ||
    msg.includes("timed out") ||
    msg.includes("aborted") ||
    msg.includes("load failed") ||
    msg.includes("connection")
  );
}
