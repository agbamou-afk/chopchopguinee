import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { useRecoveryStatus } from "@/hooks/useRecoveryStatus";

/**
 * Mandatory recovery enrollment gate for accounts created before self-service
 * recovery existed, and for signups whose enrollment did not complete.
 *
 * Runs only AFTER the user has authenticated with their existing password and
 * completed their profile, so nobody is ever locked out. The intended
 * destination is preserved through `?next=`.
 *
 * Privileged staff accounts are excluded: they keep the existing
 * `must_change_password` / AdminGuard policy and are not part of the public
 * self-service recovery system.
 */
const EXEMPT = [
  "/auth",
  "/recovery",
  "/account/recovery-setup",
  "/complete-profile",
  "/confirm-profile",
  "/no-access",
  "/admin",
  "/legal",
  "/terms",
  "/privacy",
  "/help",
  "/unsubscribe",
  "/offline",
];

export function RecoverySetupRedirect() {
  const { ready, isLoggedIn, isProfileComplete, profileLoading, isAdmin } = useAuth();
  const { configured, loading, status } = useRecoveryStatus();
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    if (!ready || profileLoading || loading) return;
    if (!isLoggedIn || !isProfileComplete || isAdmin) return;
    if (status === null) return; // status unknown (offline / RPC failure) — never block
    if (configured) return;
    if (EXEMPT.some((p) => location.pathname.startsWith(p))) return;
    const next = `${location.pathname}${location.search}`;
    navigate(`/account/recovery-setup?next=${encodeURIComponent(next)}`, { replace: true });
  }, [
    ready,
    profileLoading,
    loading,
    isLoggedIn,
    isProfileComplete,
    isAdmin,
    configured,
    status,
    location.pathname,
    location.search,
    navigate,
  ]);

  return null;
}