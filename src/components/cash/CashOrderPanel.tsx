import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import { Banknote, Loader2, AlertTriangle } from "lucide-react";
import {
  CASH_ORDER_STATE_LABEL,
  customerCancelCashOrder,
  formatGnf,
  getCashOrderRuntime,
  merchantAcceptCashOrder,
  merchantPrepareCashOrder,
  merchantRejectCashOrder,
  openCashOrderDispute,
  type CashOrderModule,
  type CashOrderRuntime,
} from "@/lib/cash/cashOrders";

type Role = "merchant" | "customer" | "driver";

interface Props {
  module: CashOrderModule;
  sourceId: string;
  role: Role;
  /** Optional preloaded runtime to avoid a round-trip in list screens. */
  runtime?: CashOrderRuntime | null;
  onChanged?: () => void;
  compact?: boolean;
}

/**
 * Single surface for the Slice 4 cash-order engine.
 *
 * Driver acceptance and cash completion are intentionally absent: they belong
 * to the canonical mission lifecycle (claim / confirm dropoff) which runs the
 * engine server-side in the same transaction.
 */
export function CashOrderPanel({ module, sourceId, role, runtime, onChanged, compact }: Props) {
  const [rt, setRt] = useState<CashOrderRuntime | null>(runtime ?? null);
  const [loading, setLoading] = useState(runtime === undefined);
  const [busy, setBusy] = useState(false);
  const [disputeOpen, setDisputeOpen] = useState(false);
  const [disputeReason, setDisputeReason] = useState("");

  const reload = useCallback(async () => {
    const r = await getCashOrderRuntime(module, sourceId);
    setRt(r);
    setLoading(false);
  }, [module, sourceId]);

  useEffect(() => {
    if (runtime !== undefined) { setRt(runtime); setLoading(false); return; }
    void reload();
  }, [runtime, reload]);

  if (loading) return null;
  if (!rt) return null;

  const run = async (fn: () => Promise<unknown>, okMsg: string) => {
    setBusy(true);
    try {
      await fn();
      toast({ title: okMsg });
      await reload();
      onChanged?.();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setBusy(false);
    }
  };

  const canMerchantDecide = role === "merchant" && rt.state === "accepted";
  const canMerchantPrepare = role === "merchant" && rt.state === "merchant_accepted";
  const canCustomerCancel =
    role === "customer" && (rt.state === "accepted");
  const canDispute =
    ["merchant_accepted", "preparing", "completed"].includes(rt.state) &&
    rt.dispute_resolution == null;

  return (
    <div className="rounded-xl border border-border/60 bg-muted/30 p-3 space-y-2">
      <div className="flex items-center justify-between gap-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary">
          <Banknote className="w-3.5 h-3.5" /> Commande espèces
        </span>
        <span className="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-card text-muted-foreground">
          {CASH_ORDER_STATE_LABEL[rt.state]}
        </span>
      </div>

      {!compact && (
        <div className="grid grid-cols-2 gap-x-3 gap-y-1 text-[11px]">
          <span className="text-muted-foreground">Marchandise</span>
          <span className="text-right tabular-nums">{formatGnf(rt.merchandise_subtotal_gnf)}</span>
          <span className="text-muted-foreground">Livraison</span>
          <span className="text-right tabular-nums">{formatGnf(rt.delivery_fee_gnf)}</span>
          <span className="text-muted-foreground">Frais CHOPCHOP</span>
          <span className="text-right tabular-nums">{formatGnf(rt.platform_fee_gnf)}</span>
          <span className="font-semibold">Espèces à encaisser</span>
          <span className="text-right font-semibold tabular-nums">{formatGnf(rt.cash_due_gnf)}</span>
        </div>
      )}

      {role === "driver" && rt.state !== "completed" && (
        <p className="text-[11px] text-muted-foreground">
          Le règlement se finalise automatiquement à la confirmation de livraison.
          Aucun gain n'est crédité en portefeuille : l'espèce est physique.
        </p>
      )}

      {rt.state === "disputed" && (
        <p className="text-[11px] text-warning inline-flex items-start gap-1">
          <AlertTriangle className="w-3 h-3 mt-0.5 shrink-0" />
          Litige en cours — les mouvements sont gelés jusqu'à décision Finance.
        </p>
      )}

      <div className="flex flex-wrap gap-1.5">
        {canMerchantDecide && (
          <>
            <Button size="sm" disabled={busy}
              onClick={() => run(() => merchantAcceptCashOrder(module, sourceId), "Marchandise financée")}>
              {busy ? <Loader2 className="w-3 h-3 animate-spin" /> : "Accepter (encaisser)"}
            </Button>
            <Button size="sm" variant="outline" disabled={busy}
              onClick={() => run(() => merchantRejectCashOrder(module, sourceId, "merchant_rejected"), "Commande refusée")}>
              Refuser
            </Button>
          </>
        )}
        {canMerchantPrepare && (
          <Button size="sm" disabled={busy}
            onClick={() => run(() => merchantPrepareCashOrder(module, sourceId), "Préparation lancée")}>
            Démarrer la préparation
          </Button>
        )}
        {canCustomerCancel && (
          <Button size="sm" variant="outline" disabled={busy}
            onClick={() => run(() => customerCancelCashOrder(module, sourceId, "customer_cancelled"), "Commande annulée")}>
            Annuler
          </Button>
        )}
        {canDispute && (
          <Button size="sm" variant="outline" disabled={busy}
            onClick={() => setDisputeOpen((v) => !v)}>
            Signaler un litige
          </Button>
        )}
      </div>

      {disputeOpen && (
        <div className="space-y-2">
          <Textarea rows={2} value={disputeReason} onChange={(e) => setDisputeReason(e.target.value)}
            placeholder="Décrivez le problème" />
          <Button size="sm" disabled={busy || disputeReason.trim().length < 4}
            onClick={() => run(async () => {
              await openCashOrderDispute(module, sourceId, disputeReason.trim());
              setDisputeOpen(false); setDisputeReason("");
            }, "Litige ouvert")}>
            Ouvrir le litige
          </Button>
        </div>
      )}
    </div>
  );
}
