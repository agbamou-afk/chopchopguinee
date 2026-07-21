/**
 * Lightweight feature-flag runtime cache.
 *
 * Reads `public.feature_flags` once at boot and exposes a synchronous
 * accessor so UI code can branch without turning every render into an
 * async query. Non-critical: on failure we fall back to safe defaults.
 *
 * This is intentionally NOT a full flag system — it exists to let us
 * archive the public CHOP Wallet without hardcoding the decision in
 * a dozen files. Add new flags to `DEFAULTS` and `KNOWN_FLAGS`.
 */
import { supabase } from "@/integrations/supabase/client";

export type FlagKey = "wallet_public_enabled";

const DEFAULTS: Record<FlagKey, boolean> = {
  // Orange Money First pivot: public CHOP Wallet UI is archived until
  // explicitly re-enabled by a Super Admin from /admin/flags.
  wallet_public_enabled: false,
};

const KNOWN_FLAGS: FlagKey[] = ["wallet_public_enabled"];

let cache: Record<FlagKey, boolean> = { ...DEFAULTS };
let loaded = false;
let inflight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function emit() {
  for (const cb of listeners) {
    try { cb(); } catch { /* ignore */ }
  }
}

export async function loadFeatureFlags(): Promise<void> {
  if (loaded) return;
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const { data, error } = await supabase
        .from("feature_flags")
        .select("key, enabled")
        .in("key", KNOWN_FLAGS);
      if (!error && Array.isArray(data)) {
        const next: Record<FlagKey, boolean> = { ...DEFAULTS };
        for (const row of data as { key: string; enabled: boolean }[]) {
          if ((KNOWN_FLAGS as string[]).includes(row.key)) {
            next[row.key as FlagKey] = !!row.enabled;
          }
        }
        cache = next;
      }
    } catch {
      // keep DEFAULTS
    } finally {
      loaded = true;
      inflight = null;
      emit();
    }
  })();
  return inflight;
}

export function getFlag(key: FlagKey): boolean {
  return cache[key];
}

export function isPublicWalletEnabled(): boolean {
  return getFlag("wallet_public_enabled");
}

export function subscribeFlags(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function flagsLoaded(): boolean {
  return loaded;
}