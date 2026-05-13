// CHOP CHOP — send-message edge function.
// Provider adapter registry. Currently ships:
//  - WhatsApp Business Cloud API (env: WHATSAPP_TOKEN, WHATSAPP_PHONE_ID)
//  - Twilio SMS                  (env: TWILIO_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM)
//  - Orange SMS                  (env: ORANGE_SMS_TOKEN, ORANGE_SMS_FROM)
//  - mock (always succeeds)      — fallback when no creds configured
//
// Frontend calls this with { template, to, vars, channelHint?, userId? }.
// Function: render template → pick channels per user prefs → try in order with retry → log every attempt to public.message_log.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

type Channel = "whatsapp" | "sms";
type TemplateKey =
  | "otp_code"
  | "welcome"
  | "topup_pending"
  | "topup_success"
  | "payment_success"
  | "refund"
  | "ride_confirmed"
  | "driver_assigned"
  | "delivery_completed"
  | "suspicious_activity";

interface SendInput {
  template: TemplateKey;
  to: string;                     // E.164, e.g. +224XXXXXXXX
  vars?: Record<string, string | number>;
  userId?: string | null;
  channelHint?: Channel;          // override prefs
  maxRetries?: number;            // per channel, default 1
}

const SIGN = "CHOP CHOP";

function fmtGNF(n: number) {
  const s = Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, "\u00A0");
  return `${s}\u00A0GNF`;
}

function renderTemplate(t: TemplateKey, vars: Record<string, string | number> = {}): string {
  const v = (k: string, fb = "") => String(vars[k] ?? fb);
  switch (t) {
    case "otp_code":
      return `${SIGN}: votre code est ${v("code")}. Ne le partagez avec personne. Valable 10 min.`;
    case "welcome":
      return `Bienvenue sur ${SIGN}, ${v("name", "ami(e)")} ! Votre compte est actif.`;
    case "topup_pending":
      return `${SIGN}: recharge de ${fmtGNF(Number(vars.amount ?? 0))} en attente. Réf ${v("ref")}. Donnez le code ${v("code")} à l'agent.`;
    case "topup_success":
      return `${SIGN}: recharge de ${fmtGNF(Number(vars.amount ?? 0))} confirmée. Réf ${v("ref")}.`;
    case "payment_success":
      return `${SIGN}: paiement de ${fmtGNF(Number(vars.amount ?? 0))} effectué. Réf ${v("ref")}.`;
    case "refund":
      return `${SIGN}: remboursement de ${fmtGNF(Number(vars.amount ?? 0))} crédité. Réf ${v("ref")}.`;
    case "ride_confirmed":
      return `${SIGN}: course ${v("mode", "moto").toUpperCase()} confirmée. Tarif ${fmtGNF(Number(vars.fare ?? 0))}.`;
    case "driver_assigned":
      return `${SIGN}: ${v("driver")} (${v("plate")}) arrive dans ${v("eta")}. Bonne route !`;
    case "delivery_completed":
      return `${SIGN}: livraison ${v("ref")} terminée. Merci !`;
    case "suspicious_activity":
      return `${SIGN} ALERTE: activité inhabituelle. Si ce n'est pas vous, changez votre PIN immédiatement.`;
  }
}

interface ProviderResult {
  ok: boolean;
  providerMessageId?: string;
  error?: string;
}

interface Provider {
  name: string;
  channel: Channel;
  available(): boolean;
  send(to: string, body: string): Promise<ProviderResult>;
}

const whatsappProvider: Provider = {
  name: "whatsapp_cloud",
  channel: "whatsapp",
  available() {
    return !!Deno.env.get("WHATSAPP_TOKEN") && !!Deno.env.get("WHATSAPP_PHONE_ID");
  },
  async send(to, body) {
    const token = Deno.env.get("WHATSAPP_TOKEN")!;
    const phoneId = Deno.env.get("WHATSAPP_PHONE_ID")!;
    const r = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: to.replace(/^\+/, ""),
        type: "text",
        text: { body },
      }),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) return { ok: false, error: `WA ${r.status}: ${JSON.stringify(data)}` };
    return { ok: true, providerMessageId: data?.messages?.[0]?.id };
  },
};

const twilioProvider: Provider = {
  name: "twilio_sms",
  channel: "sms",
  available() {
    return !!Deno.env.get("TWILIO_SID") && !!Deno.env.get("TWILIO_AUTH_TOKEN") && !!Deno.env.get("TWILIO_FROM");
  },
  async send(to, body) {
    const sid = Deno.env.get("TWILIO_SID")!;
    const tok = Deno.env.get("TWILIO_AUTH_TOKEN")!;
    const from = Deno.env.get("TWILIO_FROM")!;
    const auth = btoa(`${sid}:${tok}`);
    const form = new URLSearchParams({ To: to, From: from, Body: body });
    const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
      method: "POST",
      headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) return { ok: false, error: `Twilio ${r.status}: ${JSON.stringify(data)}` };
    return { ok: true, providerMessageId: data?.sid };
  },
};

const orangeProvider: Provider = {
  name: "orange_sms",
  channel: "sms",
  available() {
    return !!Deno.env.get("ORANGE_SMS_TOKEN") && !!Deno.env.get("ORANGE_SMS_FROM");
  },
  async send(to, body) {
    const token = Deno.env.get("ORANGE_SMS_TOKEN")!;
    const from = Deno.env.get("ORANGE_SMS_FROM")!;
    // Orange SMS API (Côte d'Ivoire / Sénégal / Guinée variant)
    const r = await fetch(
      `https://api.orange.com/smsmessaging/v1/outbound/${encodeURIComponent("tel:" + from)}/requests`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          outboundSMSMessageRequest: {
            address: `tel:${to}`,
            senderAddress: `tel:${from}`,
            outboundSMSTextMessage: { message: body },
          },
        }),
      },
    );
    const data = await r.json().catch(() => ({}));
    if (!r.ok) return { ok: false, error: `Orange ${r.status}: ${JSON.stringify(data)}` };
    return {
      ok: true,
      providerMessageId: data?.outboundSMSMessageRequest?.resourceURL ?? undefined,
    };
  },
};

const mockProvider = (channel: Channel): Provider => ({
  name: `mock_${channel}`,
  channel,
  available: () => true,
  async send(to, body) {
    console.info(`[MOCK ${channel} → ${to}]`, body);
    return { ok: true, providerMessageId: `mock-${crypto.randomUUID()}` };
  },
});

function pickProviders(channels: Channel[]): Provider[] {
  const pool: Provider[] = [whatsappProvider, twilioProvider, orangeProvider];
  const result: Provider[] = [];
  for (const ch of channels) {
    const real = pool.find((p) => p.channel === ch && p.available());
    result.push(real ?? mockProvider(ch));
  }
  return result;
}

interface Prefs {
  whatsapp_enabled: boolean;
  sms_enabled: boolean;
  preferred_channel: Channel;
}

async function loadPrefs(admin: ReturnType<typeof createClient>, userId: string | null | undefined): Promise<Prefs> {
  const fallback: Prefs = { whatsapp_enabled: true, sms_enabled: true, preferred_channel: "whatsapp" };
  if (!userId) return fallback;
  const { data } = await admin
    .from("notification_preferences")
    .select("whatsapp_enabled, sms_enabled, preferred_channel")
    .eq("user_id", userId)
    .maybeSingle();
  return (data as Prefs | null) ?? fallback;
}

function channelOrder(prefs: Prefs, hint?: Channel): Channel[] {
  if (hint) return [hint];
  const order: Channel[] =
    prefs.preferred_channel === "sms" ? ["sms", "whatsapp"] : ["whatsapp", "sms"];
  return order.filter((c) => (c === "whatsapp" ? prefs.whatsapp_enabled : prefs.sms_enabled));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const input = (await req.json()) as SendInput;
    if (!input?.template || !input?.to) {
      return new Response(JSON.stringify({ error: "template and to are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = renderTemplate(input.template, input.vars);
    const prefs = await loadPrefs(admin, input.userId);
    const order = channelOrder(prefs, input.channelHint);
    if (order.length === 0) {
      return new Response(
        JSON.stringify({ ok: false, error: "All channels disabled by user preferences" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const providers = pickProviders(order);
    const maxRetries = Math.max(0, input.maxRetries ?? 1);

    let lastError = "no provider attempted";
    for (const provider of providers) {
      let attempt = 0;
      while (attempt <= maxRetries) {
        // pre-insert log row as 'sending' so failures are recorded too
        const { data: logged, error: logErr } = await admin
          .from("message_log")
          .insert({
            user_id: input.userId ?? null,
            to_address: input.to,
            channel: provider.channel,
            provider: provider.name,
            template: input.template,
            payload: input.vars ?? {},
            body,
            status: "sending",
            retry_count: attempt,
          })
          .select("id")
          .single();
        if (logErr) console.error("log insert", logErr);
        const logId = logged?.id;

        const result = await provider.send(input.to, body);
        if (result.ok) {
          if (logId) {
            await admin
              .from("message_log")
              .update({
                status: "sent",
                provider_message_id: result.providerMessageId ?? null,
                sent_at: new Date().toISOString(),
              })
              .eq("id", logId);
          }
          return new Response(
            JSON.stringify({ ok: true, channel: provider.channel, provider: provider.name, id: logId }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
        lastError = result.error ?? "unknown";
        if (logId) {
          await admin
            .from("message_log")
            .update({ status: "failed", error: lastError })
            .eq("id", logId);
        }
        attempt += 1;
        // simple linear backoff between retries
        if (attempt <= maxRetries) await new Promise((r) => setTimeout(r, 400 * attempt));
      }
    }

    return new Response(
      JSON.stringify({ ok: false, error: lastError }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("send-message fatal", e);
    return new Response(JSON.stringify({ ok: false, error: String((e as Error).message) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
