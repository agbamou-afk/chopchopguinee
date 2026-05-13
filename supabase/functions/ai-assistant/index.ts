// CHOP CHOP — AI Assistant edge function.
// Single secure entry point for every AI call. Validates the caller's JWT,
// enforces admin gating per prompt, applies per-user rate limits, runs the
// configured prompt through the provider abstraction, and writes an audit row.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors'
import { PROMPTS, ASSISTANT_OF, type AssistantKind } from '../_shared/ai-prompts.ts'
import { getProvider, type ChatMessage } from '../_shared/ai-providers.ts'

// Per-user rate limits. Conservative defaults; tune via env if needed.
const MAX_PER_MINUTE = Number(Deno.env.get('AI_MAX_PER_MINUTE') ?? '10')
const MAX_PER_HOUR = Number(Deno.env.get('AI_MAX_PER_HOUR') ?? '120')

const FORBIDDEN_INTENT =
  /(rembours|refund|fige|freeze|bloque le portefeuille|change le prix|envoie le message|send the email)/i

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

  // 1. Authenticate caller
  const auth = req.headers.get('Authorization')
  if (!auth?.startsWith('Bearer ')) return jsonResponse({ error: 'Unauthorized' }, 401)

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  })
  const { data: claims, error: claimsErr } = await userClient.auth.getClaims(
    auth.replace('Bearer ', ''),
  )
  if (claimsErr || !claims?.claims?.sub) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }
  const userId = claims.claims.sub as string

  // 2. Parse + validate input
  let body: any
  try {
    body = await req.json()
  } catch {
    return jsonResponse({ error: 'Invalid JSON' }, 400)
  }

  const action: string = body?.action
  const input: Record<string, unknown> = body?.input ?? {}
  const userPrompt: string = typeof body?.userPrompt === 'string' ? body.userPrompt : ''

  const def = PROMPTS[action]
  if (!def) return jsonResponse({ error: `Unknown action '${action}'` }, 404)

  const assistant: AssistantKind = ASSISTANT_OF[action]
  const admin = createClient(supabaseUrl, serviceKey)

  // 3. Admin-gating
  if (def.adminOnly) {
    const { data: isAdmin } = await admin.rpc('is_any_admin', { _user_id: userId })
    if (!isAdmin) {
      await admin.from('ai_request_log').insert({
        user_id: userId,
        assistant,
        action,
        model: def.model ?? 'unknown',
        provider: 'lovable',
        status: 'blocked',
        error_message: 'admin_only',
      })
      return jsonResponse({ error: 'Admin access required' }, 403)
    }
  }

  // 4. Defensive input length cap
  const inputJson = JSON.stringify(input)
  const totalLen = inputJson.length + userPrompt.length
  if (def.maxInputChars && totalLen > def.maxInputChars) {
    return jsonResponse(
      { error: `Input too large (${totalLen} > ${def.maxInputChars} chars)` },
      413,
    )
  }

  // 5. Block obviously irreversible-action requests at the API edge
  if (FORBIDDEN_INTENT.test(userPrompt)) {
    await admin.from('ai_request_log').insert({
      user_id: userId,
      assistant,
      action,
      model: def.model ?? 'unknown',
      provider: 'lovable',
      status: 'blocked',
      error_message: 'forbidden_intent',
      prompt_summary: userPrompt.slice(0, 240),
    })
    return jsonResponse(
      {
        error:
          "L'IA ne peut pas exécuter d'action irréversible (remboursement, gel, prix, envoi). Demandez plutôt une suggestion.",
      },
      400,
    )
  }

  // 6. Per-user rate limit (best-effort, atomic upserts on minute + hour bucket)
  const now = new Date()
  const minuteBucket = new Date(Math.floor(now.getTime() / 60_000) * 60_000).toISOString()
  const hourBucket = new Date(Math.floor(now.getTime() / 3_600_000) * 3_600_000).toISOString()

  for (const [kind, bucket, max] of [
    ['minute', minuteBucket, MAX_PER_MINUTE],
    ['hour', hourBucket, MAX_PER_HOUR],
  ] as const) {
    const { data: row } = await admin
      .from('ai_rate_limits')
      .select('count')
      .eq('user_id', userId)
      .eq('window_kind', kind)
      .eq('window_start', bucket)
      .maybeSingle()
    const current = row?.count ?? 0
    if (current >= max) {
      await admin.from('ai_request_log').insert({
        user_id: userId,
        assistant,
        action,
        model: def.model ?? 'unknown',
        provider: 'lovable',
        status: 'rate_limited',
        error_message: `${kind}_limit_reached`,
      })
      return jsonResponse(
        { error: `Limite IA dépassée (${max}/${kind}). Réessayez plus tard.` },
        429,
      )
    }
    await admin.from('ai_rate_limits').upsert(
      { user_id: userId, window_kind: kind, window_start: bucket, count: current + 1 },
      { onConflict: 'user_id,window_kind,window_start' },
    )
  }

  // 7. Run the model
  const provider = getProvider(body?.provider)
  const model = body?.model || def.model || 'google/gemini-3-flash-preview'
  const messages: ChatMessage[] = [
    { role: 'system', content: def.system },
    {
      role: 'user',
      content:
        userPrompt +
        (Object.keys(input).length
          ? `\n\nDonnées contextuelles (JSON) :\n${JSON.stringify(input, null, 2)}`
          : ''),
    },
  ]

  const startedAt = Date.now()
  try {
    const result = await provider.chat({
      model,
      messages,
      jsonSchema: def.jsonSchema,
      temperature: 0.4,
    })

    const latency = Date.now() - startedAt

    await admin.from('ai_request_log').insert({
      user_id: userId,
      assistant,
      action,
      model,
      provider: provider.name,
      prompt_summary: userPrompt.slice(0, 240),
      input: input as any,
      output: { text: result.text, json: result.json ?? null } as any,
      tokens_input: result.tokensInput ?? null,
      tokens_output: result.tokensOutput ?? null,
      latency_ms: latency,
      status: 'ok',
    })

    return jsonResponse({
      ok: true,
      assistant,
      action,
      model,
      provider: provider.name,
      text: result.text,
      json: result.json ?? null,
      latencyMs: latency,
      requiresHumanApproval: true,
    })
  } catch (err: any) {
    const latency = Date.now() - startedAt
    const code: string = err?.code ?? 'gateway_error'
    const status: number = code === 'rate_limited' ? 429 : code === 'payment_required' ? 402 : 502

    await admin.from('ai_request_log').insert({
      user_id: userId,
      assistant,
      action,
      model,
      provider: provider.name,
      prompt_summary: userPrompt.slice(0, 240),
      input: input as any,
      latency_ms: latency,
      status: code === 'rate_limited' ? 'rate_limited' : 'error',
      error_message: String(err?.message ?? err).slice(0, 500),
    })

    const userMessage =
      status === 429
        ? "L'IA est momentanément surchargée. Réessayez dans une minute."
        : status === 402
        ? "Crédits IA épuisés. Contactez l'administrateur."
        : "L'IA n'a pas pu répondre. Réessayez."
    return jsonResponse({ error: userMessage }, status)
  }
})