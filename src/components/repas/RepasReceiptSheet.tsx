import { useEffect, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Separator } from "@/components/ui/separator";
import { formatGNF } from "@/lib/format";
import {
  getRepasReceipt,
  REPAS_CUSTODY_BOUNDARY_LABEL,
  repasPaymentStateLabel,
  repasReceiptTotalLabel,
  type RepasReceipt,
} from "@/lib/repas/tracking";
import { formatActivityTime } from "@/lib/activity/types";

const PAYMENT_LABEL: Record<string, string> = {
  choppay: "Chop Pay",
  cash: "Espèces",
  wallet: "Chop Pay",
};

/**
 * R7 — immutable itemized receipt. All lines and totals are frozen server-side
 * (`repas_order_receipt`); the client performs no arithmetic.
 */
export function RepasReceiptSheet({
  orderId,
  open,
  onClose,
}: {
  orderId: string | null;
  open: boolean;
  onClose: () => void;
}) {
  const [receipt, setReceipt] = useState<RepasReceipt | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !orderId) return;
    let alive = true;
    setReceipt(null);
    setError(null);
    getRepasReceipt(orderId)
      .then((r) => alive && setReceipt(r))
      .catch((e) => alive && setError(e instanceof Error ? e.message : "Reçu indisponible."));
    return () => {
      alive = false;
    };
  }, [open, orderId]);

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="bottom" className="rounded-t-3xl px-5 pb-8 pt-5 max-h-[88vh] overflow-y-auto">
        <SheetHeader className="text-left">
          <SheetTitle className="text-base font-bold">Reçu Repas</SheetTitle>
          <SheetDescription className="text-xs">
            {receipt ? receipt.restaurant.name : "Détail de la commande"}
          </SheetDescription>
        </SheetHeader>

        {!receipt && !error && <Skeleton className="mt-5 h-48 w-full rounded-2xl" />}
        {error && <p className="mt-5 text-sm text-muted-foreground">{error}</p>}

        {receipt && (
          <div className="mt-5 space-y-4">
            <div className="space-y-1.5">
              {receipt.items.map((line, i) => (
                <div key={`${line.name}-${i}`} className="flex items-start justify-between gap-3">
                  <span className="text-sm text-foreground">
                    {line.qty} × {line.name}
                  </span>
                  <span className="text-sm tabular-nums text-foreground">{formatGNF(line.line_total_gnf)}</span>
                </div>
              ))}
              {receipt.items.length === 0 && (
                <p className="text-xs text-muted-foreground">Aucun article enregistré.</p>
              )}
            </div>

            <Separator />

            <div className="space-y-1.5">
              <Line label="Sous-total articles" value={receipt.merchandise_subtotal_gnf} />
              {receipt.fulfillment === "delivery" && (
                <>
                  <Line label="Frais de livraison" value={receipt.base_delivery_fee_gnf} />
                  {receipt.promo_discount_gnf > 0 && (
                    <Line
                      label={receipt.promotion_name ? `Promotion · ${receipt.promotion_name}` : "Promotion"}
                      value={-receipt.promo_discount_gnf}
                    />
                  )}
                </>
              )}
              {receipt.platform_fee_gnf > 0 && <Line label="Frais de service" value={receipt.platform_fee_gnf} />}
            </div>

            <Separator />

            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold text-foreground">{repasReceiptTotalLabel(receipt)}</span>
              <span className="text-lg font-extrabold tabular-nums text-foreground">
                {formatGNF(receipt.order_total_gnf)}
              </span>
            </div>

            <div className="rounded-2xl bg-muted/40 px-4 py-3 space-y-1">
              <Meta label="Paiement" value={PAYMENT_LABEL[receipt.payment_method] ?? receipt.payment_method} />
              <Meta label="Statut du paiement" value={repasPaymentStateLabel(receipt.payment_state)} />
              <Meta label="Mode" value={receipt.fulfillment === "pickup" ? "Retrait sur place" : "Livraison"} />
              <Meta label="Commandé le" value={formatActivityTime(receipt.created_at)} />
              {receipt.completed_at && (
                <Meta
                  label={receipt.fulfillment === "pickup" ? "Retirée le" : "Livrée le"}
                  value={formatActivityTime(receipt.completed_at)}
                />
              )}
              {receipt.cancelled && <Meta label="Statut" value="Annulée" />}
            </div>

            {receipt.custody_timeline.length > 0 && (
              <div className="space-y-1">
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Remises confirmées</p>
                {receipt.custody_timeline.map((c, i) => (
                  <Meta
                    key={i}
                    label={REPAS_CUSTODY_BOUNDARY_LABEL[c.boundary] ?? c.boundary}
                    value={formatActivityTime(c.occurred_at)}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}

function Line({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className="text-sm tabular-nums text-foreground">{formatGNF(value)}</span>
    </div>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-[11px] text-muted-foreground">{label}</span>
      <span className="text-[11px] font-medium text-foreground">{value}</span>
    </div>
  );
}
