import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4'

/**
 * send-welcome-email
 *
 * Narrow, self-service wrapper around `send-transactional-email`.
 *
 * `send-transactional-email` deliberately rejects ordinary authenticated
 * callers: otherwise any signed-in user could send arbitrary templates
 * (security-alert, payment-receipt, otp-fallback, …) from our verified domain.
 * That gate is correct and must stay.
 *
 * A brand-new account still needs exactly one mail, and the only actor present
 * at that moment is the new user themselves. This function is the minimum
 * privilege escalation that allows it:
 *
 *   • caller must present a valid user JWT;
 *   • the recipient is ALWAYS the caller's own auth email — never a body field;
 *   • the template is ALWAYS `welcome` — never a body field;
 *   • idempotency key is derived server-side from the caller's user id, so a
 *     double submit or a remount cannot produce a second mail.
 *
 * There is therefore no way to use this endpoint to mail a third party or to
 * pick a different template.
 */

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) {
    console.error('Missing required environment variables')
    return new Response(JSON.stringify({ error: 'Server configuration error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const token = (req.headers.get('Authorization') || '')
    .replace(/^Bearer\s+/i, '')
    .trim()
  if (!token) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const admin = createClient(supabaseUrl, serviceKey)
  const { data: userData, error: userErr } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userErr || !user?.id || !user.email) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  // Only the display name is caller-supplied, and it is rendered as a React
  // prop (escaped) inside the template.
  let firstName: string | undefined
  try {
    const body = await req.json()
    const raw = typeof body?.firstName === 'string' ? body.firstName.trim() : ''
    if (raw) firstName = raw.slice(0, 60)
  } catch {
    // no body is fine
  }
  if (!firstName) {
    const meta = user.user_metadata as Record<string, unknown> | null
    const metaFirst = typeof meta?.first_name === 'string' ? meta.first_name : ''
    if (metaFirst.trim()) firstName = metaFirst.trim().slice(0, 60)
  }

  const { data, error } = await admin.functions.invoke('send-transactional-email', {
    body: {
      templateName: 'welcome',
      recipientEmail: user.email,
      idempotencyKey: `welcome-${user.id}`,
      templateData: firstName ? { firstName } : {},
    },
    headers: { Authorization: `Bearer ${serviceKey}` },
  })

  if (error) {
    console.error('welcome email dispatch failed', error.message)
    return new Response(JSON.stringify({ error: 'send_failed' }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  return new Response(JSON.stringify({ ok: true, result: data ?? null }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
