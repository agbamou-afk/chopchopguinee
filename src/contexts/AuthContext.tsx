import { createContext, useContext, useEffect, useState, ReactNode, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { Session, User } from "@supabase/supabase-js";

export type AppRole =
  | "client"
  | "driver"
  | "merchant"
  | "recharge_agent"
  | "agent"
  | "user"
  | "admin"
  | "operations_admin"
  | "finance_admin"
  | "god_admin";

export interface ProfileRecord {
  user_id: string;
  first_name: string | null;
  last_name: string | null;
  display_name: string | null;
  full_name: string | null;
  phone: string | null;
  email: string | null;
  avatar_url: string | null;
  account_status: string;
  created_at?: string | null;
  last_profile_confirmed_at?: string | null;
}

export interface FreezeRecord {
  id: string;
  user_id: string;
  reason: string;
  freeze_type: string;
  frozen_at: string;
  expires_at: string | null;
}

const ADMIN_ROLES: AppRole[] = ["admin", "operations_admin", "finance_admin", "god_admin"];

interface AuthContextValue {
  ready: boolean;
  profileLoading: boolean;
  user: User | null;
  session: Session | null;
  profile: ProfileRecord | null;
  roles: AppRole[];
  isLoggedIn: boolean;
  isAdmin: boolean;
  isGodAdmin: boolean;
  freeze: FreezeRecord | null;
  isFrozen: boolean;
  hasRole: (role: AppRole) => boolean;
  isProfileComplete: boolean;
  /**
   * True when the user has a complete profile but has not reconfirmed their
   * info in the last 60 days (or never confirmed, falling back to profile
   * created_at). False for incomplete or recently-confirmed profiles.
   */
  needsProfileReconfirmation: boolean;
  /**
   * Signup intent persisted in auth user_metadata at registration time.
   * Survives email confirmation and re-logins, unlike sessionStorage. Used
   * to route returning driver applicants to /driver/apply even before they
   * have a driver_profile row.
   */
  signupIntent: "client" | "driver" | "merchant" | null;
  requestedDriverVehicle: "moto" | "toktok" | "livraison" | null;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

function profileComplete(p: ProfileRecord | null): boolean {
  if (!p) return false;
  const hasName =
    Boolean(p.first_name?.trim() && p.last_name?.trim()) ||
    Boolean(p.full_name?.trim() || p.display_name?.trim());
  const hasPhone = Boolean(p.phone?.trim());
  return hasName && hasPhone;
}

const PROFILE_RECONFIRM_INTERVAL_MS = 60 * 24 * 60 * 60 * 1000; // 60 days

function profileNeedsReconfirmation(p: ProfileRecord | null): boolean {
  if (!p) return false;
  if (!profileComplete(p)) return false; // completion gate handles this case
  const ref = p.last_profile_confirmed_at ?? p.created_at ?? null;
  if (!ref) return false; // unknown: don't nag
  const ts = Date.parse(ref);
  if (Number.isNaN(ts)) return false;
  return Date.now() - ts >= PROFILE_RECONFIRM_INTERVAL_MS;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<ProfileRecord | null>(null);
  const [roles, setRoles] = useState<AppRole[]>([]);
  const [freeze, setFreeze] = useState<FreezeRecord | null>(null);
  const [ready, setReady] = useState(false);
  const [profileLoading, setProfileLoading] = useState(false);

  const loadProfileAndRoles = useCallback(async (userId: string, authUser?: User | null) => {
    setProfileLoading(true);
    try {
      const [{ data: prof }, { data: roleRows }, { data: freezeRows }] = await Promise.all([
        supabase
          .from("profiles")
          .select("user_id,first_name,last_name,display_name,full_name,phone,email,avatar_url,account_status,created_at,last_profile_confirmed_at")
          .eq("user_id", userId)
          .maybeSingle(),
        supabase.from("user_roles").select("role").eq("user_id", userId),
        supabase.rpc("current_freeze", { _user: userId }),
      ]);
      const freezeRow = Array.isArray(freezeRows) && freezeRows.length > 0
        ? (freezeRows[0] as FreezeRecord)
        : null;
      setFreeze(freezeRow);
      let resolved = (prof as ProfileRecord) ?? null;
      // If the profile is marked deleted OR banned, sign the user out
      // immediately and surface a clear message via toast.
      if (resolved && (resolved.account_status === "deleted" || resolved.account_status === "banned")) {
        try {
          const { toast } = await import("@/hooks/use-toast");
          if (resolved.account_status === "banned") {
            toast({
              title: "Compte suspendu",
              description:
                "Ce compte a été suspendu. Contactez le support CHOPCHOP si vous pensez qu'il s'agit d'une erreur.",
            });
          } else {
            toast({
              title: "Compte désactivé",
              description:
                "Ce compte a été supprimé. Contactez support@chopchopguinee.com pour toute question.",
            });
          }
        } catch {
          /* noop */
        }
        await supabase.auth.signOut();
        setProfile(null);
        setRoles([]);
        return;
      }
      // If the profile row is missing but auth metadata has name/phone,
      // auto-upsert once so returning users never see CompleteProfile again.
      if (!resolved && authUser) {
        const meta = (authUser.user_metadata ?? {}) as Record<string, unknown>;
        const first = (meta.first_name as string) || "";
        const last = (meta.last_name as string) || "";
        const fullMeta = (meta.full_name as string) || `${first} ${last}`.trim();
        const phone = (authUser.phone as string) || (meta.phone as string) || "";
        const email = authUser.email ?? null;
        if ((first || fullMeta) && phone) {
          const display = fullMeta || `${first} ${last}`.trim();
          const { data: upserted } = await supabase
            .from("profiles")
            .upsert(
              {
                user_id: userId,
                first_name: first || display.split(" ")[0] || null,
                last_name: last || display.split(" ").slice(1).join(" ") || null,
                full_name: display || null,
                display_name: display || null,
                phone: phone.startsWith("+") ? phone : `+${phone}`,
                email,
                last_profile_confirmed_at: new Date().toISOString(),
              },
              { onConflict: "user_id" },
            )
            .select("user_id,first_name,last_name,display_name,full_name,phone,email,avatar_url,account_status,created_at,last_profile_confirmed_at")
            .maybeSingle();
          if (upserted) resolved = upserted as ProfileRecord;
        }
      }
      setProfile(resolved);
      setRoles(((roleRows ?? []) as { role: AppRole }[]).map((r) => r.role));
    } catch {
      setProfile(null);
      setRoles([]);
      setFreeze(null);
    } finally {
      setProfileLoading(false);
    }
  }, []);

  const refresh = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    setSession(data.session ?? null);
    if (data.session?.user) await loadProfileAndRoles(data.session.user.id, data.session.user);
    else {
      setProfile(null);
      setRoles([]);
    }
  }, [loadProfileAndRoles]);

  useEffect(() => {
    let active = true;

    // 1) Subscribe FIRST to avoid missing the auth event.
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      if (!active) return;
      setSession(newSession);
      if (newSession?.user) {
        setProfileLoading(true);
        // Defer Supabase calls to avoid deadlock inside the callback.
        setTimeout(() => {
          if (active) loadProfileAndRoles(newSession.user.id, newSession.user);
        }, 0);
      } else {
        setProfile(null);
        setRoles([]);
        setFreeze(null);
      }
    });

    // 2) Then read existing session.
    (async () => {
      try {
        const res = await Promise.race([
          supabase.auth.getSession(),
          new Promise<{ data: { session: null } }>((resolve) =>
            setTimeout(() => resolve({ data: { session: null } }), 4000),
          ),
        ]);
        const s = (res as { data: { session: Session | null } }).data.session;
        if (!active) return;
        setSession(s);
        if (s?.user) await loadProfileAndRoles(s.user.id, s.user);
      } finally {
        if (active) setReady(true);
      }
    })();

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, [loadProfileAndRoles]);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    // Clear the in-session app-mode override so a new login starts clean.
    try {
      if (typeof window !== "undefined") {
        window.sessionStorage.removeItem("cc_app_mode_override");
      }
    } catch { /* noop */ }
    setSession(null);
    setProfile(null);
    setRoles([]);
    setFreeze(null);
  }, []);

  const value: AuthContextValue = {
    ready,
    profileLoading,
    user: session?.user ?? null,
    session,
    profile,
    roles,
    isLoggedIn: !!session,
    isAdmin: roles.some((r) => ADMIN_ROLES.includes(r)),
    isGodAdmin: roles.includes("god_admin"),
    freeze,
    isFrozen: !!freeze,
    hasRole: (r) => roles.includes(r),
    isProfileComplete: profileComplete(profile),
    needsProfileReconfirmation: profileNeedsReconfirmation(profile),
    signupIntent: (() => {
      const v = (session?.user?.user_metadata as Record<string, unknown> | undefined)?.signup_intent;
      return v === "driver" || v === "client" || v === "merchant" ? v : null;
    })(),
    requestedDriverVehicle: (() => {
      const v = (session?.user?.user_metadata as Record<string, unknown> | undefined)?.requested_driver_vehicle;
      return v === "moto" || v === "toktok" || v === "livraison" ? v : null;
    })(),
    refresh,
    signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within an <AuthProvider>");
  return ctx;
}

export { ADMIN_ROLES, profileComplete };