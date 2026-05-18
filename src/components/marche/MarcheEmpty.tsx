import { MARCHE_EMPTY_COPY, type MarcheEmptyKey } from "@/lib/marche";

export function MarcheEmpty({
  variant,
  action,
}: {
  variant: MarcheEmptyKey;
  action?: React.ReactNode;
}) {
  const c = MARCHE_EMPTY_COPY[variant];
  return (
    <div className="rounded-2xl bg-card border border-border/60 px-5 py-10 text-center">
      <p className="text-sm font-semibold text-foreground">{c.title}</p>
      <p className="text-xs text-muted-foreground mt-1.5">{c.hint}</p>
      {action && <div className="mt-4 flex justify-center">{action}</div>}
    </div>
  );
}