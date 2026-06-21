import { ReactNode, useEffect, useState } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { AdminModule, Capability } from "@/lib/admin/permissions";
import { supabase } from "@/integrations/supabase/client";

interface Props {
  children: ReactNode;
  module?: AdminModule;
  capability?: Capability;
}

export function AdminGuard({ children, module, capability = "view" }: Props) {
  const { ready, isLoggedIn, isProfileComplete, user } = useAuth();
  const { isAdmin, can } = useAdminAuth();
  const location = useLocation();
  const [mustChange, setMustChange] = useState<boolean | null>(null);

  useEffect(() => {
    let active = true;
    if (!isAdmin || !user?.id) { setMustChange(false); return; }
    setMustChange(null);
    supabase
      .from("admin_users")
      .select("must_change_password,status")
      .eq("user_id", user.id)
      .maybeSingle()
      .then(({ data }) => {
        if (!active) return;
        setMustChange(Boolean(data?.must_change_password) && data?.status === "active");
      });
    return () => { active = false; };
  }, [isAdmin, user?.id]);

  if (!ready || (isAdmin && mustChange === null)) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }
  if (!isLoggedIn) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/auth?next=${next}`} replace />;
  }
  if (!isProfileComplete) return <Navigate to="/complete-profile" replace />;
  if (!isAdmin) return <Navigate to="/no-access" replace />;
  if (mustChange) return <Navigate to="/admin/change-password" replace />;
  if (module && !can(module, capability)) {
    return (
      <div className="p-10 text-center">
        <h2 className="text-xl font-bold mb-2">Accès refusé</h2>
        <p className="text-sm text-muted-foreground">
          Votre rôle ne permet pas d'accéder à ce module.
        </p>
      </div>
    );
  }
  return <>{children}</>;
}