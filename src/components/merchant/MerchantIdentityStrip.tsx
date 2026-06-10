import { Store, UtensilsCrossed, ShieldCheck, Copy, Banknote } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { motion } from "framer-motion";
import type { MerchantStore } from "@/hooks/useMerchantIdentity";
import type { FoodRestaurant } from "@/lib/repas/types";
import { toast } from "@/hooks/use-toast";

interface Props {
  store: MerchantStore | null;
  restaurant: FoodRestaurant | null;
  isOpen: boolean;
  onToggleOpen: (next: boolean) => void;
}

export function MerchantIdentityStrip({ store, restaurant, isOpen, onToggleOpen }: Props) {
  const name = restaurant?.name ?? store?.name ?? "Mon commerce";
  const Icon = restaurant ? UtensilsCrossed : Store;
  const typeLabel = restaurant && store
    ? "Repas · Marché"
    : restaurant
      ? "Repas"
      : "Marché";
  const verified =
    (restaurant?.verification_state && restaurant.verification_state !== "none") ||
    (store?.verification_state && store.verification_state !== "none");
  const accountNumber = store?.merchant_account_number ?? null;
  const agentStatus = store?.service_agent_status;
  const agentBadge =
    agentStatus === "approved"
      ? { label: "Agent Wallet · Actif", tone: "bg-emerald-500/15 text-emerald-700" }
      : agentStatus === "pending"
      ? { label: "Agent Wallet · En attente", tone: "bg-amber-500/15 text-amber-800" }
      : agentStatus === "rejected"
      ? { label: "Agent Wallet · Refusé", tone: "bg-destructive/15 text-destructive" }
      : agentStatus === "disabled"
      ? { label: "Agent Wallet · Désactivé", tone: "bg-muted text-muted-foreground" }
      : null;

  const copyAccount = async () => {
    if (!accountNumber) return;
    try {
      await navigator.clipboard.writeText(accountNumber);
      toast({ title: "Copié", description: accountNumber });
    } catch {
      /* noop */
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-card rounded-2xl shadow-soft border border-border/60 p-4 space-y-3"
    >
      <div className="flex items-center gap-3">
        <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center shrink-0">
          <Icon className="w-7 h-7 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5">
            <h2 className="text-base font-extrabold text-foreground truncate">{name}</h2>
            {verified && <ShieldCheck className="w-4 h-4 text-primary shrink-0" />}
          </div>
          <p className="text-xs text-muted-foreground truncate">{typeLabel}</p>
        </div>
        <div className="flex flex-col items-end gap-1">
          <span className="text-xs font-semibold text-muted-foreground">{isOpen ? "Ouvert" : "Fermé"}</span>
          <Switch checked={isOpen} onCheckedChange={onToggleOpen} />
        </div>
      </div>
      {accountNumber && (
        <button
          type="button"
          onClick={copyAccount}
          className="w-full flex items-center justify-between gap-2 rounded-xl bg-primary/5 px-3 py-2 text-left hover:bg-primary/10 transition"
        >
          <div className="min-w-0">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground font-semibold">N° compte marchand</p>
            <p className="text-sm font-mono font-bold text-foreground truncate">{accountNumber}</p>
          </div>
          <Copy className="w-4 h-4 text-muted-foreground shrink-0" />
        </button>
      )}
      {agentBadge && (
        <div className={`flex items-center gap-1.5 text-[11px] font-semibold px-2.5 py-1 rounded-full w-fit ${agentBadge.tone}`}>
          <Banknote className="w-3 h-3" /> {agentBadge.label}
        </div>
      )}
    </motion.div>
  );
}