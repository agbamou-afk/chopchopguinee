import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import { Loader2, Scale } from "lucide-react";
import {
  CHOP_PAY_DISPUTE_OUTCOME_LABEL,
  formatGnf,
  resolveChopPayDispute,
  type ChopPayDisputeOutcome,
  type ChopPayOrderRuntime,
} from "@/lib/chopPay/chopPayOrders";

const OUTCOMES: ChopPayDisputeOutcome[] = [
  "complete_as_delivered",
  "refund_customer",
  "close_no_value",
];

/**
 * Finance / God admin surface for the Slice 5 Chop Pay dispute engine.
 * Resolution authority is enforced server-side by `_finance_privileged`.
 */
export function ChopPayDisputeQueue({ module }: { module?: "repas" | "marche" }) {
  const [rows, setRows] = useState<ChopPayOrderRuntime[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    let q = (supabase as any)
      .from("chop_pay_order_runtime")
      .select("*")
      .eq("state", "disputed")
      .order("disputed_at", { ascending: true })
      .limit(50);
    if (module) q = q.eq("source_module", module);
    const { data, error } = await q;
    setRows(error ? [] : ((data ?? []) as ChopPayOrderRuntime[]));
    setLoading(false);
  }, [module]);

  useEffect(() => { void load(); }, [load]);

  const resolve = async (r: ChopPayOrderRuntime, outcome: ChopPayDisputeOutcome) => {
    setBusy(r.id);
    try {
      await resolveChopPayDispute(r.source_module, r.source_id, outcome, note[r.id] || null);
      toast({ title: "Litige résolu" });
      await load();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Résolution impossible" });
    } finally {
      setBusy(null);
    }
  };

  return (
    <section className="rounded-2xl border border-border/60 bg-card p-4 space-y-3">
      <h2 className="text-sm font-semibold inline-flex items-center gap-2">
        <Scale className="w-4 h-4 text-primary" /> Litiges commandes Chop Pay
      </h2>
      {loading ? (
        <p className="text-sm text-muted-foreground">Chargement…</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucun litige en attente.</p>
      ) : (
        rows.map((r) => (
          <div key={r.id} className="rounded-xl border border-border/60 bg-muted/30 p-3 space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="font-semibold uppercase">{r.source_module}</span>
              <span className="text-muted-foreground">
                {r.disputed_at ? new Date(r.disputed_at).toLocaleString("fr-FR") : ""}
              </span>
            </div>
            <p className="text-[11px] text-muted-foreground font-mono break-all">{r.source_id}</p>
            <div className="grid grid-cols-2 gap-x-3 text-[11px]">
              <span className="text-muted-foreground">Marchandise</span>
              <span className="text-right tabular-nums">{formatGnf(r.merchandise_subtotal_gnf)}</span>
              <span className="text-muted-foreground">Livraison</span>
              <span className="text-right tabular-nums">{formatGnf(r.delivery_fee_gnf)}</span>
              <span className="text-muted-foreground">Frais plateforme</span>
              <span className="text-right tabular-nums">{formatGnf(r.platform_fee_gnf)}</span>
              <span className="text-muted-foreground">Total réservé</span>
              <span className="text-right tabular-nums">{formatGnf(r.order_total_gnf)}</span>
              <span className="text-muted-foreground">Gage figé coursier</span>
              <span className="text-right tabular-nums">{formatGnf(r.collateral_gnf)}</span>
            </div>
            {r.dispute_reason && (
              <p className="text-[11px] text-foreground">Motif : {r.dispute_reason}</p>
            )}
            <Textarea rows={2} placeholder="Note de résolution (audit)"
              value={note[r.id] ?? ""}
              onChange={(e) => setNote((p) => ({ ...p, [r.id]: e.target.value }))} />
            <div className="flex flex-col gap-1.5">
              {OUTCOMES.map((o) => (
                <Button key={o} size="sm" variant={o === "complete_as_delivered" ? "default" : "outline"}
                  disabled={busy === r.id} onClick={() => resolve(r, o)}>
                  {busy === r.id ? <Loader2 className="w-3 h-3 animate-spin" /> : CHOP_PAY_DISPUTE_OUTCOME_LABEL[o]}
                </Button>
              ))}
            </div>
          </div>
        ))
      )}
    </section>
  );
}
