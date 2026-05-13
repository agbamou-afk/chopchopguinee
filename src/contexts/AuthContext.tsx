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
}

const ADMIN_ROLES: AppRole[] = ["admin", "operations_admin", "finance_admin", "god_admin"];

interface AuthContextValue {
  ready: boolean;
  user: User | null;
  session: Session | null;
  profile: ProfileRecord | null;
  roles: AppRole[];
  isLoggedIn: boolean;
  isAdmin: boolean;
  isGodAdmin: boolean;
  hasRole: (role: AppRole) => boolean;
  isProfileComplete: boolean;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

function profileComplete(p: ProfileRecord | null): boolean {
  if (!p) return false;
  return Boolean(p.first_name?.trim() && p.last_name?.trim() && p.phone?.trim());
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<ProfileRecord | null>(null);
  const [roles, setRoles] = useState<AppRole[]>([]);
  const [ready, setReady] = useState(false);

  const loadProfileAndRoles = useCallback(async (userId: string) => {
    try {
      const [{ data: prof }, { data: roleRows }] = await Promise.all([
        supabase
          .from("profiles")
          .select("user_id,first_name,last_name,display_name,full_name,phone,email,avatar_url,account_status")
          .eq("user_id", userId)
          .maybeSingle(),
        supabase.from("user_roles").select("role").eq("user_id", userId),
      ]);
      setProfile((prof as ProfileRecord) ?? null);
      setRoles(((roleRows ?? []) as { role: AppRole }[]).map((r) => r.role));
    } catch {
      setProfile(null);
      setRoles([]);
    }
  }, []);

  const refresh = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    setSession(data.session ?? null);
    if (data.session?.user) await loadProfileAndRoles(data.session.user.id);
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
        // Defer Supabase calls to avoid deadlock inside the callback.
        setTimeout(() => {
          if (active) loadProfileAndRoles(newSession.user.id);
        }, 0);
      } else {
        setProfile(null);
        setRoles([]);
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
        if (s?.user) await loadProfileAndRoles(s.user.id);
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
    setSession(null);
    setProfile(null);
    setRoles([]);
  }, []);

  const value: AuthContextValue = {
    ready,
    user: session?.user ?? null,
    session,
    profile,
    roles,
    isLoggedIn: !!session,
    isAdmin: roles.some((r) => ADMIN_ROLES.includes(r)),
    isGodAdmin: roles.includes("god_admin"),
    hasRole: (r) => roles.includes(r),
    isProfileComplete: profileComplete(profile),
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