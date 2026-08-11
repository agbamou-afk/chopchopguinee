import { AlertTriangle, Loader2, Lock } from "lucide-react";
import { formatGNF } from "@/lib/format";
import { Button } from "@/components/ui/button";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  cancellationLockCopy, useCancellationQuote,
  type CancellationService,
} from "@/lib/finance/cancellation";

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  service: CancellationService;
  sourceId: string | null;
  sourceModule?: string;
  title?: string;
  /** Called only when the server says the cancellation is allowed. */
  onConfirm: () => Promise<void> | void;
  /** Optional escape hatch shown when the server locks the cancellation. */
  onDispute?: () => void;
  disputeLabel?: string;
  busy?: boolean;
};

/**
 * Slice 8 — the single customer-facing cancellation confirmation surface.
 * Every amount rendered here is a field of the server quote. The component
 * performs no percentage, basis or refund arithmetic of any kind.
 */
export function CancellationConfirmDialog({
  open, onOpenChange, service, sourceId, sourceModule,
  title = "Annuler cette commande ?", onConfirm, onDispute,
  disputeLabel = "Signaler un problème", busy = false,
}: Props) {
  const { quote, loading, error } = useCancellationQuote(service, sourceId, sourceModule, open);

  const fee = quote?.fee_gnf ?? 0;
  const isCash = quote?.payment_mode === "cash";
  const dispatched = quote?.stage === "after_dispatch";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="text-base">{title}</DialogTitle>
          <DialogDescription className="sr-only">
            Détail des frais d’annulation calculés par CHOP CHOP.
          </DialogDescription>
        </DialogHeader>

        {loading && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground py-4">
            <Loader2 className="w-4 h-4 animate-spin" /> Calcul des frais…
          </div>
        )}

        {!loading && error && (
          <p className="text-sm text-destructive py-2">
            Impossible de calculer les frais d’annulation pour le moment.
          </p>
        )}

        {!loading && quote && !quote.cancelable && (
          <div className="rounded-xl border border-border/60 bg-muted/40 p-3 space-y-1">
            <p className="text-sm text-foreground inline-flex items-start gap-2">
              <Lock className="w-4 h-4 mt-0.5 shrink-0 text-muted-foreground" />
              {cancellationLockCopy(quote.lock_reason)}
            </p>
          </div>
        )}

        {!loading && quote?.cancelable && (
          <div className="space-y-2">
            {dispatched && (
              <p className="text-sm text-foreground inline-flex items-start gap-2">
                <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0 text-warning" />
                Votre chauffeur ou coursier est déjà en route.
              </p>
            )}
            <p className="text-sm text-foreground">
              {fee > 0
                ? `Des frais d’annulation de ${formatGNF(fee)} s’appliqueront.`
                : "Aucun frais d’annulation ne s’applique."}
            </p>

            <div className="rounded-xl border border-border/60 bg-muted/30 p-3 grid grid-cols-2 gap-y-1 text-[11px]">
              <span className="text-muted-foreground">Base de calcul</span>
              <span className="text-right tabular-nums">{formatGNF(quote.basis_gnf)}</span>
              <span className="text-muted-foreground">Frais d’annulation</span>
              <span className="text-right font-semibold tabular-nums">{formatGNF(fee)}</span>
              {!isCash && (
                <>
                  <span className="text-muted-foreground">Montant restitué</span>
                  <span className="text-right tabular-nums">{formatGNF(quote.refundable_gnf)}</span>
                </>
              )}
              {isCash && quote.debt_if_cash_gnf > 0 && (
                <>
                  <span className="text-muted-foreground">À régler plus tard</span>
                  <span className="text-right tabular-nums">{formatGNF(quote.debt_if_cash_gnf)}</span>
                </>
              )}
            </div>

            {isCash && quote.debt_if_cash_gnf > 0 && (
              <p className="text-[11px] text-muted-foreground">
                Cette commande est payée en espèces : les frais deviennent un montant dû.
                Tant qu’il n’est pas réglé, vous ne pourrez plus passer de nouvelle commande
                en espèces. Votre compte reste utilisable normalement.
              </p>
            )}
          </div>
        )}

        <DialogFooter className="gap-2 sm:gap-2">
          <Button variant="ghost" size="sm" onClick={() => onOpenChange(false)} disabled={busy}>
            Revenir
          </Button>
          {quote && !quote.cancelable && onDispute && (
            <Button size="sm" variant="outline" onClick={onDispute} disabled={busy}>
              {disputeLabel}
            </Button>
          )}
          {quote?.cancelable && (
            <Button
              size="sm"
              variant="destructive"
              disabled={busy}
              onClick={() => void onConfirm()}
            >
              {busy ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : "Confirmer l’annulation"}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}