import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AdminRole, AdminModule, Capability, can } from "@/lib/admin/permissions";

interface State {
  ready: boolean;
  user: { id: string; email: string | null } | null;
  role: AdminRole | null;
}

export function useAdminAuth() {
  const [state, setState] = useState<State>({ ready: false, user: null, role: null });

  useEffect(() => {
    let active = true;
    const load = async () => {
      let session: any = null;
      try {
        const res = await Promise.race([
          supabase.auth.getSession(),
          new Promise((resolve) => setTimeout(() => resolve({ data: { session: null } }), 3000)),
        ]);
        session = (res as any)?.data?.session ?? null;
      } catch {
        session = null;
      }
      if (!active) return;
      if (!session) {
        setState({ ready: true, user: null, role: null });
        return;
      }
      let role: AdminRole | null = null;
      try {
        const queryPromise = supabase
          .from("admin_users")
          .select("admin_role,status")
          .eq("user_id", session.user.id)
          .eq("status", "active")
          .maybeSingle();
        const res: any = await Promise.race([
          queryPromise,
          new Promise((resolve) => setTimeout(() => resolve({ data: null }), 4000)),
        ]);
        role = (res?.data?.admin_role as AdminRole) ?? null;
      } catch {
        role = null;
      }
      if (!active) return;
      setState({
        ready: true,
        user: { id: session.user.id, email: session.user.email ?? null },
        role,
      });
    };
    load();
    const { data: sub } = supabase.auth.onAuthStateChange(() => load());
    return () => { active = false; sub.subscription.unsubscribe(); };
  }, []);

  return {
    ...state,
    isAdmin: !!state.role,
    isSuperAdmin: state.role === "super_admin",
    can: (module: AdminModule, cap: Capability = "view") => can(state.role, module, cap),
  };
}