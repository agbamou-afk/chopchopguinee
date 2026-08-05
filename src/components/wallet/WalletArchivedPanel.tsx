import { Smartphone, ShieldCheck, History, LifeBuoy } from "lucide-react";
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { OmPaymentsList } from "./OmPaymentsList";

/**
 * Rendered on /wallet when Chop Pay is not yet publicly enabled
 * (`chop_pay_enabled` / legacy `wallet_public_enabled` both off).
 * The internal ledger is NOT touched — this panel simply reframes the
 * surface honestly: cash is the launch payment model and Orange Money is
 * kept only as a manual top-up rail, never as a direct checkout method.
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
      <ScreenHeader
        title="Chop Pay"
        subtitle="Paiement en espèces · rechargement Orange Money vérifié par un opérateur."
      />

      <div className="px-4 mt-4 space-y-4 pb-24">
        <section className="rounded-3xl gradient-wallet-premium text-primary-foreground p-5 relative overflow-hidden shadow-wallet">
          <div className="pointer-events-none absolute -top-16 -right-8 w-48 h-48 rounded-full bg-white/10 blur-3xl" aria-hidden />
          <div className="flex items-center gap-2 opacity-95 mb-2">
            <span className="inline-flex items-center justify-center w-8 h-8 rounded-xl bg-white/12 ring-1 ring-white/15">
              <Smartphone className="w-4 h-4" />
            </span>
            <p className="text-[11px] uppercase tracking-[0.22em] font-semibold">
              Chop Pay · bientôt disponible
            </p>
          </div>
          <h2 className="text-xl font-extrabold leading-tight">
            Payez en espèces, rechargez avec Orange Money.
          </h2>
          <p className="text-sm opacity-90 mt-2 leading-relaxed">
            Le solde Chop Pay n'est pas encore ouvert au public. Vos
            rechargements Orange Money restent vérifiés manuellement par
            un opérateur CHOPCHOP.
          </p>
          <Button
            onClick={onOpenOm}
            className="mt-4 w-full h-11 bg-white text-primary hover:bg-white/90 font-semibold"
          >
            Recharger avec Orange Money
          </Button>
        </section>

        <OmPaymentsList />

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