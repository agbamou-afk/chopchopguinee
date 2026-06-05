import { useEffect, useRef, useState } from "react";

export const UNDER_CONSTRUCTION_DELAY_MS = 1000;


/**
 * Per-user dismissal key. Logged-out visitors fall back to a session-scoped
 * key so the popup never trails them across sessions when no identity exists.
 */
function storageKey(userId: string | null): string {
  return `cc_under_construction_seen:${userId ?? "guest"}`;
}

function alreadySeen(userId: string | null): boolean {
  if (typeof window === "undefined") return true;
  try {
    if (userId) {
      return localStorage.getItem(storageKey(userId)) === "1";
    }
    return sessionStorage.getItem(storageKey(null)) === "1";
  } catch {
    return false;
  }
}

function markSeen(userId: string | null) {
  if (typeof window === "undefined") return;
  try {
    if (userId) {
      localStorage.setItem(storageKey(userId), "1");
    } else {
      sessionStorage.setItem(storageKey(null), "1");
    }
  } catch { /* noop */ }
}

interface Options {
  /** True only when the user is fully inside the product shell (no onboarding,
   *  no blocking modal, no auth screen, etc.). */
  canShow: boolean;
  /** Current user id, or null for logged-out visitors. */
  userId: string | null;
  /** Delay before opening, ms. Defaults to 1s. */
  delayMs?: number;
}

/**
 * Schedules the "CHOPCHOP arrive bientôt" announcement.
 *
 * The hook stays idle until `canShow` is true, then waits `delayMs` before
 * flipping `open` to true. Dismissal is persisted per user (localStorage) or
 * per session for guests.
 */
export function useUnderConstructionAnnouncement({
  canShow,
  userId,
  delayMs = UNDER_CONSTRUCTION_DELAY_MS,
}: Options) {
  const [open, setOpen] = useState(false);
  const scheduledRef = useRef(false);
  const shownRef = useRef(false);
  // Captured at mount: whether this user/guest had already dismissed UC
  // before this session started. Drives `willShow` so callers can decide
  // whether to wait on UC or proceed with their own scheduling.
  const [seenAtMount] = useState(() => alreadySeen(userId));
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (!canShow) return;
    if (scheduledRef.current || shownRef.current) return;
    if (alreadySeen(userId)) return;
    scheduledRef.current = true;
    const t = window.setTimeout(() => {
      // Re-check just before opening — a blocking flow might have appeared.
      if (alreadySeen(userId)) return;
      shownRef.current = true;
      setOpen(true);
    }, delayMs);
    return () => {
      window.clearTimeout(t);
      scheduledRef.current = false;
    };
  }, [canShow, userId, delayMs]);

  const close = () => {
    markSeen(userId);
    setOpen(false);
    setDismissed(true);
  };

  return {
    open,
    close,
    /** UC will (or might still) appear in this session. */
    willShow: !seenAtMount && !dismissed,
  };
}