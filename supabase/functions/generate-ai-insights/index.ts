// CHOP CHOP — Generate AI insights from analytics_summary().
// Admin-only. Calls the Lovable AI Gateway, stores results in `ai_insights`.
// AI is governance-bounded: it summarizes and recommends, it never decides.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors'

const MODEL = 'google/gemini-3-flash-preview'

const SYSTEM = `Tu es l'analyste IA de CHOP CHOP, super-app guinéenne (mobilité, repas, marché, portefeuille).
À partir des métriques agrégées fournies, génère 4 à 8 INSIGHTS concis en français clair, classés par utilité opérationnelle.

Règles strictes :
- N'invente JAMAIS de chiffre, de quartier, d'agent, de chauffeur ou de marchand.
- Cite uniquement des données présentes dans le contexte JSON fourni.
- Chaque insight propose UNE action humaine concrète (jamais d'action automatique).
- L'IA ne peut PAS rembourser, geler, bannir, modifier les prix, ni envoyer de message. Recommande seulement.
- Sois bref. Maximum 2 phrases par insight.

Réponds STRICTEMENT au format JSON :
{ "insights": [
  { "section": "executive|behavior|mobility|wallet|marketplace|driver|merchant|fraud|growth|recommendation",
    "title": "...",
    "summary": "...",
    "recommendation": "...",
    "confidence": "low|medium|high",
    "metrics": { ... } }
] }`

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
  const lovableKey = Deno.env.get('LOVABLE_API_KEY')!

  const auth = req.headers.get('Authorization')
  if (!auth?.startsWith('Bearer ')) return jsonResponse({ error: 'Unauthorized' }, 401)

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  })
  const { data: claims } = await userClient.auth.getClaims(auth.replace('Bearer ', ''))
  const userId = claims?.claims?.sub as string | undefined
  if (!userId) return jsonResponse({ error: 'Unauthorized' }, 401)

  const admin = createClient(supabaseUrl, serviceKey)
  const { data: isAdmin } = await admin.rpc('is_any_admin', { _user_id: userId })
  if (!isAdmin) return jsonResponse({ error: 'Admin access required' }, 403)

  const body = await req.json().catch(() => ({}))
  const days = Math.min(Math.max(Number(body?.days ?? 7), 1), 30)

  const { data: summary, error: sumErr } = await userClient.rpc('analytics_summary', {
    p_days: days,
  })
  if (sumErr) return jsonResponse({ error: sumErr.message }, 500)

  // Call Lovable AI Gateway
  const aiRes = await fetch('https://ai.gateway.lovable.dev/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${lovableKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: 'system', content: SYSTEM },
        {
          role: 'user',
          content:
            `Métriques agrégées CHOP CHOP (${days} derniers jours) :\n` +
            JSON.stringify(summary, null, 2),
        },
      ],
      response_format: { type: 'json_object' },
    }),
  })

  if (!aiRes.ok) {
    const text = await aiRes.text().catch(() => '')
    return jsonResponse({ error: `AI gateway ${aiRes.status}: ${text.slice(0, 200)}` }, 502)
  }

  const aiJson = await aiRes.json()
  const text: string = aiJson?.choices?.[0]?.message?.content ?? '{}'
  let parsed: { insights?: any[] }
  try {
    parsed = JSON.parse(text)
  } catch {
    return jsonResponse({ error: 'AI returned non-JSON output' }, 502)
  }

  const insights = Array.isArray(parsed.insights) ? parsed.insights : []
  if (insights.length === 0) return jsonResponse({ ok: true, inserted: 0, summary })

  const today = new Date().toISOString().slice(0, 10)
  const rows = insights
    .filter((i) => i?.title && i?.summary)
    .slice(0, 12)
    .map((i) => ({
      section: ['executive','behavior','mobility','wallet','marketplace','driver','merchant','fraud','growth','recommendation'].includes(i.section) ? i.section : 'executive',
      title: String(i.title).slice(0, 200),
      summary: String(i.summary).slice(0, 800),
      recommendation: i.recommendation ? String(i.recommendation).slice(0, 400) : null,
      confidence: ['low', 'medium', 'high'].includes(i.confidence) ? i.confidence : 'medium',
      metrics: i.metrics ?? {},
      generated_for_date: today,
      generated_by_user_id: userId,
      status: 'new',
    }))

  const { error: insErr } = await admin.from('ai_insights').insert(rows)
  if (insErr) return jsonResponse({ error: insErr.message }, 500)

  return jsonResponse({ ok: true, inserted: rows.length, summary })
})