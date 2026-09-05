import { ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { AdminModule, Capability } from "@/lib/admin/permissions";
import { useAdminAuth } from "@/hooks/useAdminAuth";

interface Props {
  module: AdminModule;
  capability?: Capability;
  children: ReactNode;
}

/**
 * Route-level module gate for admin pages that do not render a <ModulePage>.
 * UI gating is cosmetic only — the database capability layer stays authoritative.
 */
export function AdminRouteGuard({ module, capability = "view", children }: Props) {
  const { can, role } = useAdminAuth();
  if (can(module, capability)) return <>{children}</>;
  return (
    <div className="max-w-6xl mx-auto p-6">
      <Card className="p-8 text-center border-dashed">
        <h2 className="text-base font-semibold mb-1">Accès refusé</h2>
        <p className="text-sm text-muted-foreground">
          Votre rôle ({role ?? "—"}) ne dispose pas de la permission «{capability}» sur le module «{module}».
        </p>
      </Card>
    </div>
  );
}
