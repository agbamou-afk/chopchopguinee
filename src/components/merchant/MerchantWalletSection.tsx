import { useMemo, useState } from "react";
import {
  Wallet as WalletIcon, Clock, Info, Loader2, Send, ShieldAlert, CheckCircle2, XCircle,
  Receipt as ReceiptIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";
import {
  useMerchantFinance, createMerchantSettlementRequest, type MerchantSettlementRequest,
} from "@/lib/finance/readModels";
import {
  fetchMerchantSettlementReceipt, type MerchantSettlementReceipt,
} from "@/lib/finance/payouts";

const STATUS_COPY: Record<MerchantSettlementRequest["status"], { label: string; tone: string }> = {
  requested: { label: "Demandé", tone: "bg-secondary/20 text-secondary-foreground border-secondary/40" },
  pending_review: { label: "En vérification", tone: "bg-secondary/20 text-secondary-foreground border-secondary/40" },
  rejected: { label: "Refusé", tone: "bg-destructive/10 text-destructive border-destructive/30" },
  cancelled: { label: "Annulé", tone: "bg-muted text-muted-foreground border-border" },
  settled: { label: "Réglé", tone: "bg-success/10 text-success border-success/30" },
};

/**
 * Slice 7 — merchant ledger-truth surface.
 *
 * Every amount below is returned by `merchant_finance_overview` /
 * `merchant_settlement_requests_list`. No client-side arithmetic.
 * Settlement is REQUEST-ONLY: no Orange Money is sent, no merchant funds
 * are debited, and nothing shows as "Réglé" without canonical evidence.
 */
export function MerchantWalletSection() {
  const { overview, requests, loading, refresh } = useMerchantFinance();
  const [amount, setAmount] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [receipt, setReceipt] = useState<MerchantSettlementReceipt | null>(null);
  const [receiptFor, setReceiptFor] = useState<string | null>(null);

  const eligible = overview?.eligible_settlement_gnf ?? 0;
  const parsedAmount = useMemo(() => {
    const n = Number((amount || "").replace(/\s/g, ""));
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  }, [amount]);

  const submit = async () => {
    if (parsedAmount <= 0) return;
    setSubmitting(true);
    const res = await createMerchantSettlementRequest({
      amountGnf: parsedAmount,
      idempotencyKey: `msr-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
      note: "Demande de règlement marchand",
    });
    setSubmitting(false);
    if (res.ok === false) {
      const message = res.error;
      toast.error(
        message.includes("AMOUNT_EXCEEDS_ELIGIBLE")
          ? "Montant supérieur au montant éligible confirmé par le serveur."
          : "Demande impossible pour le moment.",
      );
      return;
    }
    toast.success(res.duplicate ? "Demande déjà enregistrée." : "Demande de règlement enregistrée.");
    setAmount("");
    void refresh();
  };

  const openReceipt = async (requestId: string) => {
    setReceiptFor(requestId);
    setReceipt(await fetchMerchantSettlementReceipt(requestId));
  };

  return (
    <div className="space-y-3">
      {/* Sales balance */}
      <div className="bg-card rounded-2xl border border-border/60 p-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl gradient-wallet flex items-center justify-center">
            <WalletIcon className="w-5 h-5 text-primary-foreground" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs text-muted-foreground">Solde des ventes · CHOP Wallet marchand</p>
            <p className="text-xl font-extrabold text-foreground tabular-nums">
              {loading ? "…" : formatGNF(overview?.sales_balance_gnf ?? 0)}
            </p>
            <p className="text-[11px] text-muted-foreground tabular-nums">
              Disponible {formatGNF(overview?.available_gnf ?? 0)} · Bloqué {formatGNF(overview?.held_gnf ?? 0)}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 mt-3">
          <div className="rounded-lg bg-muted/40 p-2">
            <p className="text-[10px] text-muted-foreground">À régler (en attente)</p>
            <p className="text-xs font-bold text-foreground tabular-nums">
              {formatGNF(overview?.pending_payable_gnf ?? 0)}
            </p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2">
            <p className="text-[10px] text-muted-foreground">Financé, non réglé</p>
            <p className="text-xs font-bold text-foreground tabular-nums">
              {formatGNF(overview?.funded_unsettled_gnf ?? 0)}
            </p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2">
            <p className="text-[10px] text-muted-foreground">Déjà réglé</p>
            <p className="text-xs font-bold text-foreground tabular-nums">
              {formatGNF(overview?.settled_total_gnf ?? 0)}
            </p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2">
            <p className="text-[10px] text-muted-foreground">Remboursé / annulé</p>
            <p className="text-xs font-bold text-foreground tabular-nums">
              {formatGNF(overview?.reversed_total_gnf ?? 0)}
            </p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2 col-span-2">
            <p className="text-[10px] text-muted-foreground">Réservé pour règlement (non débité)</p>
            <p className="text-xs font-bold text-foreground tabular-nums">
              {formatGNF(overview?.reserved_for_settlement_gnf ?? 0)}
            </p>
          </div>
        </div>
      </div>

      {/* Settlement request — request only */}
      <div className="bg-card rounded-2xl border border-border/60 p-4">
        <h3 className="font-bold text-foreground mb-1">Demande de règlement</h3>
        <p className="text-[11px] text-muted-foreground">
          Montant éligible confirmé par le serveur :{" "}
          <span className="font-semibold text-foreground tabular-nums">{formatGNF(eligible)}</span>
          {(overview?.open_request_gnf ?? 0) > 0 && (
            <> · déjà demandé : <span className="tabular-nums">{formatGNF(overview!.open_request_gnf)}</span></>
          )}
        </p>

        <div className="mt-3 flex gap-2">
          <Input
            inputMode="numeric"
            placeholder="Montant en GNF"
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/[^\d]/g, ""))}
            disabled={eligible <= 0 || submitting}
          />
          <Button onClick={submit} disabled={eligible <= 0 || parsedAmount <= 0 || submitting}>
            {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            <span className="ml-1">Demander</span>
          </Button>
        </div>

        <div className="mt-3 rounded-xl bg-muted/40 border border-border/60 p-3 flex items-start gap-2">
          <ShieldAlert className="w-4 h-4 text-muted-foreground mt-0.5 shrink-0" />
          <p className="text-[11px] text-muted-foreground">
            Le versement externe Orange Money n'est pas encore activé. Une demande est
            <span className="font-semibold text-foreground"> enregistrée pour vérification manuelle</span> :
            le montant est réservé, aucun argent n'est envoyé et votre solde n'est débité que
            lorsqu'un virement sortant réel est prouvé et réconcilié.
          </p>
        </div>
      </div>

      {/* Settlement history */}
      <div className="bg-card rounded-2xl border border-border/60 p-4">
        <h3 className="font-bold text-foreground mb-2">Historique des règlements</h3>
        {loading ? (
          <p className="text-xs text-muted-foreground">Chargement…</p>
        ) : requests.length === 0 ? (
          <div className="rounded-xl bg-muted/40 border border-border/60 p-3 flex items-start gap-2">
            <Info className="w-4 h-4 text-muted-foreground mt-0.5 shrink-0" />
            <div className="text-xs text-muted-foreground">
              <p className="font-semibold text-foreground">Aucune demande de règlement.</p>
              <p className="mt-0.5">Vos demandes et règlements confirmés apparaîtront ici.</p>
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            {requests.map((r) => {
              const copy = STATUS_COPY[r.status];
              const Icon = r.status === "settled" ? CheckCircle2 : r.status === "rejected" ? XCircle : Clock;
              return (
                <div key={r.id} className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-muted flex items-center justify-center text-muted-foreground">
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">
                      {formatGNF(r.amount_gnf)}
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      {new Date(r.created_at).toLocaleString("fr-FR")}
                      {r.reject_reason ? ` · ${r.reject_reason}` : ""}
                    </p>
                  </div>
                  <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${copy.tone}`}>
                    {copy.label}
                  </span>
                  <Button size="sm" variant="ghost" onClick={() => void openReceipt(r.id)}>
                    <ReceiptIcon className="w-4 h-4" />
                  </Button>
                </div>
              );
            })}
          </div>
        )}

        {receiptFor && (
          <div className="mt-3 rounded-xl bg-muted/40 border border-border/60 p-3 text-[11px] text-muted-foreground">
            {receipt?.receipt_available ? (
              <div className="space-y-0.5">
                <p className="font-semibold text-foreground">Reçu de règlement</p>
                <p>Montant réglé : <span className="tabular-nums">{formatGNF(receipt.merchant_liability_debit_gnf)}</span></p>
                <p>Reçu par vous : <span className="tabular-nums">{formatGNF(receipt.recipient_net_gnf)}</span> ·
                  frais {formatGNF(receipt.provider_fee_gnf)} ({receipt.fee_borne_by === "platform" ? "plateforme" : "bénéficiaire"})</p>
                <p>Référence {receipt.provider} : <span className="font-mono">{receipt.provider_reference}</span></p>
                <p>Vers {receipt.destination_msisdn} · {new Date(receipt.settled_at).toLocaleString("fr-FR")}</p>
              </div>
            ) : (
              <p>{receipt && !receipt.receipt_available ? receipt.message : "Aucun règlement externe prouvé pour cette demande."}</p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
