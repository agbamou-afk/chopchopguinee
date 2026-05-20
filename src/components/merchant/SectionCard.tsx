import { ReactNode } from "react";

interface Props {
  title: string;
  hint?: string;
  children: ReactNode;
  action?: ReactNode;
}

export function SectionCard({ title, hint, children, action }: Props) {
  return (
    <section className="bg-card rounded-2xl shadow-card border border-border/60 p-4 space-y-3">
      <header className="flex items-center justify-between gap-2">
        <div className="min-w-0">
          <h3 className="text-sm font-extrabold text-foreground">{title}</h3>
          {hint && <p className="text-xs text-muted-foreground truncate">{hint}</p>}
        </div>
        {action}
      </header>
      <div>{children}</div>
    </section>
  );
}