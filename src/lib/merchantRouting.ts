import { supabase } from "@/integrations/supabase/client";

export const MERCHANT_INTENT_STORAGE_KEY = "cc_signup_merchant_intent";
export const MERCHANT_ONBOARDING_SLIDES_PATH = "/merchant/onboarding-slides";
export const MERCHANT_ONBOARDING_PATH = "/merchant/onboarding";
export const MERCHANT_HUB_PATH = "/merchant/hub";
export const MERCHANT_APPLY_PATH = "/merchant/apply";

export function hasStoredMerchantIntent(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return window.sessionStorage.getItem(MERCHANT_INTENT_STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

export function storeMerchantIntent(): void {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(MERCHANT_INTENT_STORAGE_KEY, "1");
  } catch {
    /* noop */
  }
}

export function clearMerchantIntent(): void {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.removeItem(MERCHANT_INTENT_STORAGE_KEY);
  } catch {
    /* noop */
  }
}

export async function persistMerchantAppMode(userId: string): Promise<void> {
  await (supabase as any)
    .from("user_preferences")
    .upsert({ user_id: userId, app_mode: "merchant" }, { onConflict: "user_id" });
}

export async function resolveMerchantPostAuthRoute(
  userId: string,
  opts: { preferSlides?: boolean } = {},
): Promise<string> {
  const { data: store } = await (supabase as any)
    .from("merchant_stores")
    .select("id")
    .eq("owner_user_id", userId)
    .maybeSingle();

  if (store?.id) return MERCHANT_HUB_PATH;

  if (!opts.preferSlides) return MERCHANT_ONBOARDING_PATH;

  const { data: prefs } = await (supabase as any)
    .from("user_preferences")
    .select("merchant_slides_completed_at")
    .eq("user_id", userId)
    .maybeSingle();

  return prefs?.merchant_slides_completed_at
    ? MERCHANT_ONBOARDING_PATH
    : MERCHANT_ONBOARDING_SLIDES_PATH;
}