import { ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { AdminModule, Capability } from "@/lib/admin/permissions";
import { useAdminAuth } from "@/hooks/useAdminAuth";

interface Props {
  module: AdminModule;
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  children?: ReactNode;
  requireCapability?: Capability;
}

export function ModulePage({ module, title, subtitle, actions, children, requireCapability = "view" }: Props) {
  const { can, role } = useAdminAuth();
  const allowed = can(module, requireCapability);

  return (
    <div className="space-y-6 max-w-6xl mx-auto">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
          {subtitle && <p className="text-sm text-muted-foreground mt-1">{subtitle}</p>}
        </div>
        {actions && <div className="flex items-center gap-2">{actions}</div>}
      </div>
      {!allowed ? (
        <Card className="p-10 text-center">
          <p className="text-sm text-muted-foreground">
            Votre rôle ({role ?? "—"}) ne dispose pas de la permission «{requireCapability}» sur ce module.
          </p>
        </Card>
      ) : (
        children
      )}
    </div>
  );
}

export function ComingSoon({ description }: { description: string }) {
  return (
    <Card className="p-8 border-dashed">
      <p className="text-sm text-muted-foreground">{description}</p>
      <p className="text-xs text-muted-foreground mt-3">
        Squelette en place. La logique métier sera implémentée dans la prochaine phase.
      </p>
    </Card>
  );
}