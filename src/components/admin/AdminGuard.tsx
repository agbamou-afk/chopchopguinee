import { ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { AdminModule, Capability } from "@/lib/admin/permissions";

interface Props {
  children: ReactNode;
  module?: AdminModule;
  capability?: Capability;
}

export function AdminGuard({ children, module, capability = "view" }: Props) {
  const { ready, isAdmin, can } = useAdminAuth();
  if (!ready) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }
  if (!isAdmin) return <Navigate to="/auth?next=/admin" replace />;
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