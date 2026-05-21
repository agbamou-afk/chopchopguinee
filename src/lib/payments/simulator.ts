/**
 * Provider event simulator.
 *
 * Drives the SAME validation + reconciliation pathway a real webhook
 * would. Used by:
 *   - the admin Payments panel (test buttons)
 *   - the sandbox engine (scripted scenarios)
 *
 * Wallet credits only happen via `confirm_payment_intent` SECURITY
 * DEFINER RPC, which is admin-gated server-side.
 */
import type { PaymentIntent } from "./types";
import type { NormalizedProviderEvent, SimulatedKind } from "./providers/types";
import { getProviderAdapter } from "./providers/registry";
import { validateProviderEvent } from "./webhooks";
import { confirmIntent, failIntent, getIntent } from "./intents";

export interface SimulateResult {
  event: NormalizedProviderEvent;
  applied: "confirmed" | "failed" | "expired" | "ignored";
  reason?: string;
}

/**
 * Simulate a provider event for an existing intent. The function:
 *   1. Re-fetches the intent (fresh state).
 *   2. Asks the provider adapter to synthesize a normalized event.
 *   3. Validates it (idempotency, amount, provider, terminal checks).
 *   4. Dispatches confirm/fail RPC accordingly.
 *
 * Returns the outcome so the admin UI / sandbox can render it.
 */
export async function simulateProviderForIntent(
  intentId: string,
  kind: SimulatedKind,
  opts: { phone_number?: string; knownProviderRefs?: Set<string> } = {},
): Promise<SimulateResult> {
  const fresh = await getIntent(intentId);
  if (!fresh) {
    throw new Error("Intent introuvable.");
  }
  const adapter = getProviderAdapter(fresh.provider);
  if (!adapter) {
    throw new Error(`Aucun adaptateur pour ${fresh.provider}.`);
  }

  const event = adapter.simulateProviderEvent(fresh, kind, { phone_number: opts.phone_number });

  // Build a "lookup intent" for validation. For unknown_reference we deliberately
  // pass null to exercise the unknown-reference rule.
  const lookupIntent =
    kind === "unknown_reference" ? null : fresh;

  const validation = validateProviderEvent(event, lookupIntent, {
    knownProviderRefs: opts.knownProviderRefs,
  });

  if (!validation.ok) {
    return { event, applied: "ignored", reason: (validation as { reason: string }).reason };
  }

  if (event.state === "confirmed") {
    await confirmIntent(intentId, event.provider_reference, `simulated:${kind}`);
    return { event, applied: "confirmed" };
  }
  if (event.state === "failed") {
    await failIntent(intentId, `simulated:${kind}`);
    return { event, applied: "failed" };
  }
  if (event.state === "expired") {
    await failIntent(intentId, `simulated:expired`);
    return { event, applied: "expired" };
  }
  // pending / processing — no terminal action
  return { event, applied: "ignored", reason: `state:${event.state}` };
}