/**
 * Orange Money webhook — PROTECTED STUB.
 *
 * This function is intentionally disabled by default. It does NOT process
 * money, NOT credit wallets, NOT trust the payload. It exists so a public
 * URL can be registered later with Orange Money for sandbox testing —
 * gated behind a feature flag until WONGO is contractually live.
 *
 * Future flow (TODO(live-provider)):
 *   request
 *     -> verify signature (HMAC-SHA256, server-side secret)
 *     -> parse provider payload via orangeMoneyAdapter.parseWebhookEvent
 *     -> load payment_intent by internal_reference
 *     -> validateProviderEvent(event, intent)
 *     -> append payment_reconciliation_events row (always, even on reject)
 *     -> on confirmed -> confirm_payment_intent RPC (idempotent, server-side)
 *     -> on failed/expired -> fail_payment_intent RPC
 *     -> respond 2xx fast (idempotent)
 *
 * Hard rules:
 *   - No live credentials in this file.
 *   - No wallet writes from this file directly — only via SECURITY DEFINER RPCs.
 *   - No payload value is ever logged.
 */
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

const ENABLED_FLAG = "ENABLE_ORANGE_MONEY_WEBHOOKS";

function safeJson(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only POST is ever accepted.
  if (req.method !== "POST") {
    return safeJson({ error: "method_not_allowed" }, 405);
  }

  // Feature flag must be explicitly enabled. Default = disabled.
  const enabled = (Deno.env.get(ENABLED_FLAG) ?? "").toLowerCase() === "true";
  if (!enabled) {
    // Safe generic response — no internal detail leaked.
    return safeJson({ error: "webhook_disabled" }, 403);
  }

  // TODO(live-provider): verify HMAC-SHA256 signature from
  //   header `X-Orange-Signature` against ORANGE_MONEY_WEBHOOK_SECRET.
  // TODO(live-provider): parse payload via orangeMoneyAdapter.parseWebhookEvent.
  // TODO(live-provider): load intent by internal_reference (service role).
  // TODO(live-provider): run validateProviderEvent(event, intent).
  // TODO(live-provider): append payment_reconciliation_events row.
  // TODO(live-provider): dispatch confirm_payment_intent / fail_payment_intent RPC.
  // TODO(live-provider): support provider status lookup + reconciliation report ingest.
  // TODO(live-provider): support payout callbacks once disbursement API is live.

  // Until live wiring is reviewed and shipped, accept the request shape
  // but explicitly refuse to act on it.
  let hasJsonBody = false;
  try {
    const ct = req.headers.get("content-type") ?? "";
    if (ct.includes("application/json")) {
      await req.json().catch(() => undefined);
      hasJsonBody = true;
    }
  } catch {
    // ignore — we never log payload contents
  }

  console.info("orange_money_webhook_stub_invoked", {
    method: req.method,
    hasJsonBody,
    // Intentionally NOT logging headers, payload, or signature.
  });

  return safeJson({ status: "accepted_stub", processed: false }, 202);
});
