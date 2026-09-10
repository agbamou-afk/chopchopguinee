const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * admin-create-staff-user — RETIRED (G3).
 *
 * Staff provisioning now goes exclusively through the governed lifecycle saga
 * `admin-staff-lifecycle` (idempotency key, four-eyes binding, Auth-identity
 * recording before authority finalization, machine-readable outcomes).
 *
 * This endpoint is kept only as an explicit tombstone so that any stale client
 * receives a precise refusal instead of silently provisioning authority through
 * an ungoverned second path. It performs NO writes of any kind.
 */
Deno.serve((req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return new Response(
    JSON.stringify({
      ok: false,
      result: "ENDPOINT_RETIRED",
      message:
        "Cette voie de création est retirée. Utilisez la console Administrateurs : le cycle de vie staff gouverné est le seul chemin autorisé.",
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
