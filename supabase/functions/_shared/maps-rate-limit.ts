import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

export async function checkMapsRateLimit(
  admin: ReturnType<typeof createClient>,
  userId: string,
  kind: 'route' | 'eta',
  limit: number,
): Promise<{ allowed: boolean; remaining: number }> {
  const windowStart = new Date();
  windowStart.setSeconds(0, 0);
  const iso = windowStart.toISOString();

  const { data: existing } = await admin
    .from('maps_rate_limits')
    .select('count')
    .eq('user_id', userId)
    .eq('window_kind', kind)
    .eq('window_start', iso)
    .maybeSingle();

  const next = (existing?.count ?? 0) + 1;
  if (next > limit) return { allowed: false, remaining: 0 };

  await admin
    .from('maps_rate_limits')
    .upsert(
      { user_id: userId, window_kind: kind, window_start: iso, count: next },
      { onConflict: 'user_id,window_kind,window_start' },
    );

  return { allowed: true, remaining: limit - next };
}

export async function logMapsRequest(
  admin: ReturnType<typeof createClient>,
  row: {
    user_id: string | null;
    provider: string;
    action: string;
    input: unknown;
    output_summary?: unknown;
    status?: 'ok' | 'error';
    error_message?: string | null;
    latency_ms?: number;
  },
) {
  try {
    await admin.from('maps_request_log').insert({
      user_id: row.user_id,
      provider: row.provider,
      action: row.action,
      input: row.input,
      output_summary: row.output_summary ?? null,
      status: row.status ?? 'ok',
      error_message: row.error_message ?? null,
      latency_ms: row.latency_ms ?? null,
    });
  } catch {
    // best-effort
  }
}