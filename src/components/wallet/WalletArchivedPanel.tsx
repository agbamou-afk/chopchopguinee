import { Smartphone, ShieldCheck, History, LifeBuoy } from "lucide-react";
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { ScreenHeader } from "@/components/ui/ScreenHeader";

/**
 * Rendered on /wallet when `wallet_public_enabled` is off (Orange Money
 * First pivot). The internal ledger is NOT touched — this panel simply
 * reframes the surface so no user is told they have a public "wallet
 * balance" that would imply instant top-up automation.
 */
export function WalletArchivedPanel({
  onOpenOm,
  onOpenActivity,
}: {
  onOpenOm: () => void;
  onOpenActivity: () => void;
}) {
  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader title="Paiements" subtitle="Orange Money" />

      <div className="px-4 mt-4 space-y-4 pb-24">
        <section className="rounded-3xl gradient-wallet-premium text-primary-foreground p-5 relative overflow-hidden shadow-wallet">
          <div className="pointer-events-none absolute -top-16 -right-8 w-48 h-48 rounded-full bg-white/10 blur-3xl" aria-hidden />
          <div className="flex items-center gap-2 opacity-95 mb-2">
            <span className="inline-flex items-center justify-center w-8 h-8 rounded-xl bg-white/12 ring-1 ring-white/15">
              <Smartphone className="w-4 h-4" />
            </span>
            <p className="text-[11px] uppercase tracking-[0.22em] font-semibold">
              Paiement Orange Money
            </p>
          </div>
          <h2 className="text-xl font-extrabold leading-tight">
            CHOP Wallet est désactivé pour ce lancement.
          </h2>
          <p className="text-sm opacity-90 mt-2 leading-relaxed">
            Les paiements passent par Orange Money.<br />
            Vos transactions restent suivies par CHOPCHOP.
          </p>
          <Button
            onClick={onOpenOm}
            className="mt-4 w-full h-11 bg-white text-primary hover:bg-white/90 font-semibold"
          >
            Payer avec Orange Money
          </Button>
        </section>

        <section className="rounded-2xl bg-card border border-border/60 p-4 space-y-3">
          <div className="flex items-start gap-3">
            <div className="p-2 rounded-xl bg-primary/10 shrink-0">
              <ShieldCheck className="w-4 h-4 text-primary" />
            </div>
            <div className="text-sm text-foreground/90">
              <p className="font-semibold">Vérification opérateur</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Chaque paiement Orange Money est vérifié par un opérateur CHOPCHOP.
                Aucun crédit automatique sans validation.
              </p>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <div className="p-2 rounded-xl bg-primary/10 shrink-0">
              <History className="w-4 h-4 text-primary" />
            </div>
            <div className="text-sm text-foreground/90">
              <p className="font-semibold">Suivi de vos paiements</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Retrouvez l'historique de vos paiements Orange Money dans Activité.
              </p>
            </div>
          </div>
        </section>

        <div className="grid grid-cols-2 gap-2">
          <Button variant="outline" className="h-11" onClick={onOpenActivity}>
            <History className="w-4 h-4 mr-2" /> Activité
          </Button>
          <Link to="/help/issues">
            <Button variant="outline" className="w-full h-11">
              <LifeBuoy className="w-4 h-4 mr-2" /> Signalements
            </Button>
          </Link>
        </div>

        <p className="text-[11px] text-muted-foreground text-center px-4">
          Le suivi interne de vos paiements reste actif. CHOPCHOP conserve
          l'historique pour la comptabilité et le support.
        </p>
      </div>
    </div>
  );
}