import { Car, ShoppingBag, Store } from "lucide-react";
import { motion } from "framer-motion";
import { useAccountMode } from "@/hooks/useAccountMode";
import { useAppMode, useSwitchAppMode } from "@/hooks/useAppMode";
import type { AccountMode } from "@/lib/identity/accountMode";
import { cn } from "@/lib/utils";

const META: Record<AccountMode, { label: string; hint: string; icon: typeof Car }> = {
  client: { label: "Client", hint: "Commander et se déplacer", icon: ShoppingBag },
  driver: { label: "Chauffeur", hint: "Espace de travail chauffeur", icon: Car },
  merchant: { label: "Marchand", hint: "Espace de travail marchand", icon: Store },
};

/**
 * Node 5 · A8 — the single canonical account/mode switcher.
 *
 * Only server-approved workspaces are rendered. Switching changes the view,
 * never the account's identity, capabilities, approvals or money.
 */
export function ModeSwitcher({ className }: { className?: string }) {
  const { availableModes, canSwitch, loading } = useAccountMode();
  const { effectiveMode, mode } = useAppMode();
  const switchAppMode = useSwitchAppMode();
  const current = (effectiveMode ?? mode ?? "client") as AccountMode;

  if (loading || !canSwitch) return null;

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className={cn("bg-card rounded-2xl p-4 shadow-card border border-border/60", className)}
    >
      <p className="text-sm font-bold text-foreground">Espace de travail</p>
      <p className="text-xs text-muted-foreground mb-3">
        Changer d'espace modifie seulement l'affichage, jamais votre compte.
      </p>
      <div className="grid grid-cols-2 gap-2" role="group" aria-label="Choisir un espace">
        {availableModes.map((m) => {
          const meta = META[m];
          const active = current === m;
          const Icon = meta.icon;
          return (
            <button
              key={m}
              type="button"
              aria-pressed={active}
              onClick={() => { if (!active) switchAppMode(m); }}
              className={cn(
                "flex items-center gap-2 rounded-xl border p-3 text-left transition-colors",
                active
                  ? "border-primary bg-primary/10"
                  : "border-border hover:bg-muted/50",
              )}
            >
              <span className={cn("p-2 rounded-lg", active ? "bg-primary/20" : "bg-muted")}>
                <Icon className={cn("w-4 h-4", active ? "text-primary" : "text-muted-foreground")} />
              </span>
              <span className="min-w-0">
                <span className="block text-sm font-semibold text-foreground">{meta.label}</span>
                <span className="block text-[11px] text-muted-foreground truncate">{meta.hint}</span>
              </span>
            </button>
          );
        })}
      </div>
    </motion.div>
  );
}
