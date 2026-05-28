import { supabase } from "@/integrations/supabase/client";

/** Current legal document versions. Bump these to force re-acceptance. */
export const TERMS_VERSION = "2026-05-27-v1";
export const PRIVACY_VERSION = "2026-05-27-v1";
export const LEGAL_LAST_UPDATED = "2026-05-27";

export interface LegalAcceptanceRow {
  user_id: string;
  terms_version: string;
  privacy_version: string;
  accepted_at: string;
  source: string;
}

/**
 * Check whether the given user has accepted the current Terms and Privacy
 * versions. Returns false on any error (gate fail-closed for sensitive
 * actions; render is fail-open via the consent hook).
 */
export async function hasAcceptedCurrentLegal(userId: string): Promise<boolean> {
  if (!userId) return false;
  const { data, error } = await (supabase as any)
    .from("user_legal_consents")
    .select("terms_version, privacy_version")
    .eq("user_id", userId)
    .eq("terms_version", TERMS_VERSION)
    .eq("privacy_version", PRIVACY_VERSION)
    .order("accepted_at", { ascending: false })
    .limit(1);
  if (error) return false;
  return Array.isArray(data) && data.length > 0;
}

/**
 * Record a legal acceptance for the currently authenticated user. Idempotent
 * by intent — extra rows are harmless because the table is append-only.
 */
export async function recordLegalAcceptance(opts: {
  source?: "signup" | "modal" | "settings";
} = {}): Promise<{ ok: boolean; error?: string }> {
  const { data: sess } = await supabase.auth.getSession();
  const uid = sess.session?.user.id;
  if (!uid) return { ok: false, error: "not_authenticated" };
  const userAgent =
    typeof navigator !== "undefined" ? navigator.userAgent.slice(0, 240) : null;
  const { error } = await (supabase as any).from("user_legal_consents").insert({
    user_id: uid,
    terms_version: TERMS_VERSION,
    privacy_version: PRIVACY_VERSION,
    accepted_terms: true,
    accepted_privacy: true,
    source: opts.source ?? "modal",
    user_agent: userAgent,
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}