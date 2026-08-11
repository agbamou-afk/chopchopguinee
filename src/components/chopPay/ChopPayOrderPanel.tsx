import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import { Wallet, Loader2, AlertTriangle, Lock } from "lucide-react";
import {
  CHOP_PAY_STATE_LABEL,
  authorizeChopPayOrder,
  customerCancelChopPayOrder,
  formatGnf,
  getChopPayRuntime,
  merchantAcceptChopPayOrder,
  merchantPrepareChopPayOrder,
  merchantRejectChopPayOrder,
  openChopPayDispute,
  type ChopPayModule,
  type ChopPayOrderRuntime,
} from "@/lib/chopPay/chopPayOrders";
import { CancellationConfirmDialog } from "@/components/finance/CancellationConfirmDialog";

type Role = "merchant" | "customer" | "driver";

interface Props {
  module: ChopPayModule;
  sourceId: string;
  role: Role;
  /** Optional preloaded runtime to avoid a round-trip in list screens. */
  runtime?: ChopPayOrderRuntime | null;
  /** Show the customer authorization CTA when no runtime exists yet. */
  allowAuthorize?: boolean;
  onChanged?: () => void;
  compact?: boolean;
}

/**
 * Single surface for the Slice 5 Chop Pay order engine.
 *
 * Courier collateral and settlement are intentionally absent as buttons: they
 * belong to the canonical mission lifecycle, which runs the engine server-side
 * using the collateral frozen at authorization (DEF-FIN-S5-001).
 */
export function ChopPayOrderPanel({
  module,
  sourceId,
  role,
  runtime,
  allowAuthorize,
  onChanged,
  compact,
}: Props) {
  const [rt, setRt] = useState<ChopPayOrderRuntime | null>(runtime ?? null);
  const [loading, setLoading] = useState(runtime === undefined);
  const [busy, setBusy] = useState(false);
  const [disputeOpen, setDisputeOpen] = useState(false);
  const [disputeReason, setDisputeReason] = useState("");

  const reload = useCallback(async () => {
    const r = await getChopPayRuntime(module, sourceId);
    setRt(r);
    setLoading(false);
  }, [module, sourceId]);

  useEffect(() => {
    if (runtime !== undefined) { setRt(runtime); setLoading(false); return; }
    void reload();
  }, [runtime, reload]);

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

  if (loading) return null;

  if (!rt) {
    if (!allowAuthorize || role !== "customer") return null;
    return (
      <div className="rounded-xl border border-border/60 bg-muted/30 p-3 space-y-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary">
          <Wallet className="w-3.5 h-3.5" /> Chop Pay
        </span>
        <p className="text-[11px] text-muted-foreground">
          Le montant total est réservé sur votre solde Chop Pay. Le marchand n'est
          payé qu'à l'acceptation, et le coursier à la livraison.
        </p>
        <Button size="sm" disabled={busy}
          onClick={() => run(() => authorizeChopPayOrder(module, sourceId), "Paiement autorisé")}>
          {busy ? <Loader2 className="w-3 h-3 animate-spin" /> : "Autoriser le paiement"}
        </Button>
      </div>
    );
  }

  const canMerchantDecide = role === "merchant" && ["authorized", "accepted"].includes(rt.state);
  const canMerchantPrepare = role === "merchant" && rt.state === "merchant_accepted";
  const canCustomerCancel =
    role === "customer" && ["authorized", "accepted"].includes(rt.state);
  const canDispute =
    ["merchant_accepted", "preparing", "completed"].includes(rt.state) &&
    rt.dispute_resolution == null;

  return (
    <div className="rounded-xl border border-border/60 bg-muted/30 p-3 space-y-2">
      <div className="flex items-center justify-between gap-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary">
          <Wallet className="w-3.5 h-3.5" /> Commande Chop Pay
        </span>
        <span className="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-card text-muted-foreground">
          {CHOP_PAY_STATE_LABEL[rt.state]}
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
          <span className="font-semibold">Total réservé</span>
          <span className="text-right font-semibold tabular-nums">{formatGnf(rt.order_total_gnf)}</span>
        </div>
      )}

      {role === "driver" && (rt.collateral_gnf ?? 0) > 0 && (
        <p className="text-[11px] text-muted-foreground inline-flex items-start gap-1">
          <Lock className="w-3 h-3 mt-0.5 shrink-0" />
          Gage de mission bloqué : {formatGnf(rt.collateral_gnf)} — figé à l'autorisation
          de la commande, restitué {rt.state === "completed" ? "à la livraison" : "en fin de mission"}.
        </p>
      )}

      {role === "driver" && rt.state !== "completed" && (
        <p className="text-[11px] text-muted-foreground">
          Aucune espèce à encaisser : le client a déjà payé via Chop Pay. Votre gain
          est crédité automatiquement à la confirmation de livraison.
        </p>
      )}

      {rt.state === "completed" && (rt.driver_earning_gnf ?? 0) > 0 && role === "driver" && (
        <p className="text-[11px] text-foreground">
          Gain crédité : <span className="font-semibold">{formatGnf(rt.driver_earning_gnf)}</span>
        </p>
      )}

      {(rt.cancellation_charge_gnf ?? 0) > 0 && role === "customer" && (
        <p className="text-[11px] text-muted-foreground">
          Frais d'annulation retenus : {formatGnf(rt.cancellation_charge_gnf)} ·
          remboursé : {formatGnf(rt.customer_refunded_gnf)}
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
              onClick={() => run(() => merchantAcceptChopPayOrder(module, sourceId), "Commande acceptée · marchand payé")}>
              {busy ? <Loader2 className="w-3 h-3 animate-spin" /> : "Accepter (encaisser)"}
            </Button>
            <Button size="sm" variant="outline" disabled={busy}
              onClick={() => run(() => merchantRejectChopPayOrder(module, sourceId, "merchant_rejected"), "Commande refusée")}>
              Refuser
            </Button>
          </>
        )}
        {canMerchantPrepare && (
          <Button size="sm" disabled={busy}
            onClick={() => run(() => merchantPrepareChopPayOrder(module, sourceId), "Préparation lancée")}>
            Démarrer la préparation
          </Button>
        )}
        {canCustomerCancel && (
          <Button size="sm" variant="outline" disabled={busy}
            onClick={() => setCancelOpen(true)}>
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
              await openChopPayDispute(module, sourceId, disputeReason.trim());
              setDisputeOpen(false); setDisputeReason("");
            }, "Litige ouvert")}>
            Ouvrir le litige
          </Button>
        </div>
      )}

      <CancellationConfirmDialog
        open={cancelOpen}
        onOpenChange={setCancelOpen}
        service="chop_pay_order"
        sourceId={sourceId}
        sourceModule={module}
        busy={busy}
        onConfirm={async () => {
          await run(
            () => customerCancelChopPayOrder(module, sourceId, "customer_cancelled"),
            "Commande annulée",
          );
          setCancelOpen(false);
        }}
        onDispute={() => { setCancelOpen(false); setDisputeOpen(true); }}
        disputeLabel="Signaler un litige"
      />
    </div>
  );
}
