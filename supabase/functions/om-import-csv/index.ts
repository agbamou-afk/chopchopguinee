import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type Row = {
  provider_transaction_id: string;
  payer_phone: string | null;
  amount_gnf: number;
  status: string;
  event_type?: string;
  raw: Record<string, string>;
};

function parseCSV(text: string): Record<string, string>[] {
  const lines = text.replace(/\r/g, "").split("\n").filter((l) => l.trim().length > 0);
  if (lines.length === 0) return [];
  const split = (line: string): string[] => {
    const out: string[] = [];
    let cur = "";
    let inQ = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c === '"') { inQ = !inQ; continue; }
      if (c === "," && !inQ) { out.push(cur); cur = ""; continue; }
      cur += c;
    }
    out.push(cur);
    return out.map((s) => s.trim());
  };
  const headers = split(lines[0]).map((h) => h.toLowerCase().replace(/\s+/g, "_"));
  return lines.slice(1).map((l) => {
    const cells = split(l);
    const obj: Record<string, string> = {};
    headers.forEach((h, i) => { obj[h] = cells[i] ?? ""; });
    return obj;
  });
}

function normalize(r: Record<string, string>): Row | null {
  const tx =
    r.transaction_id || r.tx_id || r.id || r.reference_id || r.ref_id;
  if (!tx) return null;
  const amountRaw = r.amount_gnf || r.amount || r.montant || "0";
  const amount = parseInt(amountRaw.replace(/[^\d-]/g, ""), 10);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  const phone = r.payer_phone || r.from_msisdn || r.msisdn || r.payer || r.phone || null;
  const rawStatus = (r.status || r.state || "successful").toLowerCase();
  const status =
    ["successful", "success", "completed", "ok"].includes(rawStatus) ? "successful"
    : ["failed", "error", "ko"].includes(rawStatus) ? "failed"
    : rawStatus;
  return {
    provider_transaction_id: tx,
    payer_phone: phone,
    amount_gnf: amount,
    status,
    event_type: r.event_type || "payment.received",
    raw: r,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: auth } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: roles } = await admin.from("user_roles").select("role").eq("user_id", user.id);
    const allowed = (roles ?? []).some((r: { role: string }) =>
      ["god_admin", "finance_admin", "admin"].includes(r.role)
    );
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const csv: string = body.csv ?? "";
    if (typeof csv !== "string" || csv.length < 10) {
      return new Response(JSON.stringify({ error: "csv field is required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rows = parseCSV(csv);
    const summary = {
      total: rows.length,
      imported: 0,
      duplicates: 0,
      auto_matched: 0,
      credited: 0,
      needs_review: 0,
      rejected: 0,
      errors: [] as string[],
    };

    for (const raw of rows) {
      const row = normalize(raw);
      if (!row) { summary.rejected++; continue; }

      // Dedup by provider_transaction_id
      const { data: existing } = await admin
        .from("payment_provider_events")
        .select("id")
        .eq("provider_transaction_id", row.provider_transaction_id)
        .eq("provider", "orange_money")
        .maybeSingle();

      if (existing) { summary.duplicates++; continue; }

      const { data: ev, error: insErr } = await admin
        .from("payment_provider_events")
        .insert({
          provider: "orange_money",
          provider_transaction_id: row.provider_transaction_id,
          event_type: row.event_type ?? "payment.received",
          payer_phone: row.payer_phone,
          amount_gnf: row.amount_gnf,
          status: row.status,
          processing_status: "received",
          raw_payload: row.raw,
        })
        .select("id")
        .single();
      if (insErr || !ev) { summary.errors.push(insErr?.message ?? "insert failed"); continue; }
      summary.imported++;

      const { data: matchResult, error: matchErr } = await admin.rpc("om_auto_match", {
        p_event_id: ev.id,
      });
      if (matchErr) { summary.errors.push(matchErr.message); continue; }
      const status = (matchResult as { status?: string } | null)?.status;
      if (status === "credited") { summary.auto_matched++; summary.credited++; }
      else if (status === "needs_review") summary.needs_review++;
      else if (status === "rejected") summary.rejected++;
    }

    const { data: cfgRow } = await admin
      .from("app_settings").select("value").eq("key", "orange_money").maybeSingle();
    const merged = { ...((cfgRow?.value as Record<string, unknown>) ?? {}), last_import_at: new Date().toISOString() };
    await admin.from("app_settings").update({ value: merged as never }).eq("key", "orange_money");

    return new Response(JSON.stringify({ summary }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});