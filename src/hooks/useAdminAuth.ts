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
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        if (active) setState({ ready: true, user: null, role: null });
        return;
      }
      const { data } = await supabase
        .from("admin_users")
        .select("admin_role,status")
        .eq("user_id", session.user.id)
        .eq("status", "active")
        .maybeSingle();
      if (!active) return;
      setState({
        ready: true,
        user: { id: session.user.id, email: session.user.email ?? null },
        role: (data?.admin_role as AdminRole) ?? null,
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