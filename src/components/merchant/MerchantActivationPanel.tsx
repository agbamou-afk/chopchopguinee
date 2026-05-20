import { useState } from "react";
import { motion } from "framer-motion";
import { Store, UtensilsCrossed, Truck, Wallet, Sparkles } from "lucide-react";
import { StoreOnboardingSheet } from "@/components/marche/StoreOnboardingSheet";
import { RestaurantOnboardingSheet } from "@/components/food/RestaurantOnboardingSheet";

interface Props {
  onActivated?: () => void;
  variant?: "full" | "compact";
}

/**
 * Calm activation surface shown when a user without merchant capability
 * enters a merchant-related area. Offers two lightweight entry points
 * (boutique Marché, restaurant Repas) instead of forcing role selection.
 */
export function MerchantActivationPanel({ onActivated, variant = "full" }: Props) {
  const [storeOpen, setStoreOpen] = useState(false);
  const [restoOpen, setRestoOpen] = useState(false);

  const compact = variant === "compact";

  return (
    <>
      <div className={compact ? "space-y-3" : "max-w-md mx-auto px-4 py-8 space-y-5"}>
        {!compact && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-center space-y-2"
          >
            <div className="w-14 h-14 mx-auto rounded-2xl gradient-wallet flex items-center justify-center">
              <Sparkles className="w-7 h-7 text-primary-foreground" />
            </div>
            <h2 className="text-xl font-extrabold text-foreground">
              Activez votre espace marchand
            </h2>
            <p className="text-sm text-muted-foreground">
              Vendez sur Marché ou ouvrez votre restaurant Repas. Aucun compte séparé, tout reste dans CHOP.
            </p>
          </motion.div>
        )}

        <button
          onClick={() => setStoreOpen(true)}
          className="w-full text-left bg-card border border-border/60 rounded-2xl p-4 flex items-start gap-3 shadow-card hover:bg-muted/40 transition"
        >
          <div className="p-2 rounded-xl bg-primary/10">
            <Store className="w-5 h-5 text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="font-semibold text-foreground">Créer une boutique</p>
            <p className="text-xs text-muted-foreground">
              Vendez vos produits sur CHOP Marché, avec ou sans livraison.
            </p>
          </div>
        </button>

        <button
          onClick={() => setRestoOpen(true)}
          className="w-full text-left bg-card border border-border/60 rounded-2xl p-4 flex items-start gap-3 shadow-card hover:bg-muted/40 transition"
        >
          <div className="p-2 rounded-xl bg-secondary/15">
            <UtensilsCrossed className="w-5 h-5 text-secondary-foreground" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="font-semibold text-foreground">Créer un restaurant</p>
            <p className="text-xs text-muted-foreground">
              Recevez des commandes Repas, en retrait ou livraison.
            </p>
          </div>
        </button>

        {!compact && (
          <div className="grid grid-cols-2 gap-3 pt-1">
            <div className="bg-muted/40 rounded-2xl p-3 flex items-start gap-2">
              <Truck className="w-4 h-4 text-muted-foreground mt-0.5" />
              <p className="text-[11px] text-muted-foreground leading-snug">
                Livraison CHOP activable à tout moment.
              </p>
            </div>
            <div className="bg-muted/40 rounded-2xl p-3 flex items-start gap-2">
              <Wallet className="w-4 h-4 text-muted-foreground mt-0.5" />
              <p className="text-[11px] text-muted-foreground leading-snug">
                CHOPPay s'active depuis l'espace marchand.
              </p>
            </div>
          </div>
        )}
      </div>

      <StoreOnboardingSheet
        open={storeOpen}
        onOpenChange={setStoreOpen}
        onCreated={() => onActivated?.()}
      />
      <RestaurantOnboardingSheet
        open={restoOpen}
        onOpenChange={setRestoOpen}
        onCreated={() => onActivated?.()}
      />
    </>
  );
}