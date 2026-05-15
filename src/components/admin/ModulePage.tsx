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
    <div className="space-y-4 max-w-6xl mx-auto">
      <div className="flex items-end justify-between gap-4 border-b border-border/60 pb-2">
        <div className="min-w-0">
          <p className="admin-eyebrow">{module}</p>
          <h1 className="text-[18px] font-semibold tracking-tight leading-tight mt-0.5">{title}</h1>
          {subtitle && <p className="text-[12px] text-muted-foreground mt-0.5">{subtitle}</p>}
        </div>
        {actions && <div className="flex items-center gap-2 shrink-0">{actions}</div>}
      </div>
      {!allowed ? (
        <Card className="p-8 text-center border-dashed">
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