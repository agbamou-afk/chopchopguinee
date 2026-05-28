import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import {
  hasAcceptedCurrentLegal,
  recordLegalAcceptance,
  TERMS_VERSION,
  PRIVACY_VERSION,
} from "@/lib/legal";

export interface LegalConsentGate {
  ready: boolean;
  needsAcceptance: boolean;
  accepting: boolean;
  termsVersion: string;
  privacyVersion: string;
  accept: () => Promise<{ ok: boolean; error?: string }>;
  refresh: () => Promise<void>;
}

/**
 * Tracks whether the current logged-in user has accepted the latest Terms
 * and Privacy versions. Public/logged-out visitors never trigger a prompt.
 * Fail-open: while loading or on error we do NOT block the UI.
 */
export function useLegalConsentGate(): LegalConsentGate {
  const { isLoggedIn, user, ready: authReady } = useAuth();
  const [ready, setReady] = useState(false);
  const [needsAcceptance, setNeedsAcceptance] = useState(false);
  const [accepting, setAccepting] = useState(false);

  const check = useCallback(async () => {
    if (!authReady) return;
    if (!isLoggedIn || !user?.id) {
      setNeedsAcceptance(false);
      setReady(true);
      return;
    }
    const ok = await hasAcceptedCurrentLegal(user.id);
    setNeedsAcceptance(!ok);
    setReady(true);
  }, [authReady, isLoggedIn, user?.id]);

  useEffect(() => {
    void check();
  }, [check]);

  const accept = useCallback(async () => {
    setAccepting(true);
    const res = await recordLegalAcceptance({ source: "modal" });
    setAccepting(false);
    if (res.ok) setNeedsAcceptance(false);
    return res;
  }, []);

  return {
    ready,
    needsAcceptance,
    accepting,
    termsVersion: TERMS_VERSION,
    privacyVersion: PRIVACY_VERSION,
    accept,
    refresh: check,
  };
}

/** Route prefixes that require accepted legal before use. */
export const SENSITIVE_ROUTE_PREFIXES = [
  "/wallet",
  "/ride",
  "/repas/checkout",
  "/marche/checkout",
  "/driver",
  "/merchant",
  "/support/new",
  "/agent",
];

export function isSensitiveRoute(pathname: string): boolean {
  return SENSITIVE_ROUTE_PREFIXES.some((p) => pathname.startsWith(p));
}