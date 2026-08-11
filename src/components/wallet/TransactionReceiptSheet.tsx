import { useEffect, useState } from "react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { ShieldCheck, Receipt, AlertTriangle, Loader2 } from "lucide-react";
import { formatGNF } from "@/lib/format";
import { ReportIssueButton } from "@/components/support/ReportIssueButton";
import { fetchCustomerReceipt, type CustomerReceipt } from "@/lib/finance/readModels";
import {
  mapTxnStatus,
  stateLabel,
  statePhrase,
  stateTone,
  isWongoReference,
} from "@/lib/payments";

interface Props {
  /** Canonical wallet transaction id. The sheet fetches its own truth. */
  transactionId: string | null;
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

/**
 * Slice 7 — receipt truth comes from `customer_receipt`. Nothing financial is
 * read from a client-held transaction row, and there is no fallback to raw
 * values when the read model is unavailable.
 */
export function TransactionReceiptSheet({ transactionId, open, onOpenChange }: Props) {
  const [receipt, setReceipt] = useState<CustomerReceipt | null>(null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    if (!open || !transactionId) { setReceipt(null); setFailed(false); return; }
    setLoading(true); setFailed(false); setReceipt(null);
    void fetchCustomerReceipt(transactionId).then((r) => {
      if (cancelled) return;
      setReceipt(r);
      setFailed(!r);
      setLoading(false);
    });
    return () => { cancelled = true; };
  }, [open, transactionId]);

  if (!transactionId) return null;

  const body = (() => {
    if (loading) {
      return (
        <div className="mt-10 flex flex-col items-center gap-2 text-muted-foreground">
          <Loader2 className="w-5 h-5 animate-spin" />
          <p className="text-xs">Chargement du reçu…</p>
        </div>
      );
    }
    if (failed || !receipt) {
      return (
        <div className="mt-8 text-center space-y-3">
          <div className="mx-auto w-12 h-12 rounded-2xl bg-muted flex items-center justify-center">
            <AlertTriangle className="w-5 h-5 text-muted-foreground" />
          </div>
          <p className="text-sm font-semibold text-foreground">Reçu indisponible</p>
          <p className="text-xs text-muted-foreground max-w-[18rem] mx-auto">
            Nous n'avons pas pu récupérer le reçu officiel de cette opération. Réessayez
            plus tard ou signalez le problème.
          </p>
          <ReportIssueButton
            className="w-full"
            issueTypes={["payment_pending", "payment_failed", "other"]}
            context={{ metadata: { transaction_id: transactionId, surface: "receipt_unavailable" } }}
          />
        </div>
      );
    }
    return <ReceiptBody receipt={receipt} />;
  })();

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl max-h-[90vh] overflow-y-auto">
        <SheetHeader className="text-left">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-xl bg-primary/10">
              <Receipt className="w-5 h-5 text-primary" />
            </div>
            <div>
              <SheetTitle>Reçu</SheetTitle>
              <SheetDescription className="text-xs">Détail du paiement</SheetDescription>
            </div>
          </div>
        </SheetHeader>
        {body}
      </SheetContent>
    </Sheet>
  );
}

function ReceiptBody({ receipt }: { receipt: CustomerReceipt }) {
  const direction = receipt.direction;
  const paymentState = mapTxnStatus(receipt.status);
  const stateText = stateLabel(paymentState);
  const statePhrs = statePhrase(paymentState);
  const toneKey = stateTone(paymentState);
  const refIsWongo = isWongoReference(receipt.reference);
  const dateStr = new Date(receipt.created_at).toLocaleString("fr-FR", {
    day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit",
  });
  const completedStr = receipt.completed_at
    ? new Date(receipt.completed_at).toLocaleString("fr-FR", {
        day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit",
      })
    : null;

  return (
        <div className="mt-5 space-y-4">
          <div className="text-center">
            <p className="text-xs text-muted-foreground">{receipt.module}</p>
            <p className={`text-3xl font-extrabold tabular-nums mt-1 ${direction === "in" ? "text-[hsl(160_55%_28%)]" : "text-foreground"}`}>
              {direction === "in" ? "+" : "-"}{formatGNF(Math.abs(receipt.amount_gnf))}
            </p>
            <span className={`inline-block mt-2 text-[11px] font-semibold px-2 py-0.5 rounded-full border ${statusTone(toneKey)}`}>
              {stateText}
            </span>
            <p className="mt-1 text-[11px] text-muted-foreground">{statePhrs}</p>
          </div>

          <div className="bg-card rounded-2xl border border-border/60 p-4 space-y-2.5 shadow-card">
            <Row label="Date" value={dateStr} />
            {completedStr && <Row label="Confirmé le" value={completedStr} />}
            <Row label="Type" value={receipt.kind} />
            {receipt.description && <Row label="Détail" value={receipt.description} />}
            <Row label={refIsWongo ? "Référence CHOP" : "Référence"} value={receipt.reference} mono />
            <Row label="Transaction" value={receipt.transaction_id} mono />
            <Row
              label="Provenance comptable"
              value={receipt.has_journal_provenance ? "Écriture comptable vérifiée" : "Non rattachée à une écriture"}
            />
          </div>

          <div className="flex items-center gap-2 text-[11px] text-muted-foreground justify-center">
            <ShieldCheck className="w-3.5 h-3.5 text-primary" />
            Transaction sécurisée par ChopPay
          </div>

          <ReportIssueButton
            className="w-full"
            issueTypes={["payment_pending", "payment_failed", "other"]}
            context={{
              metadata: {
                transaction_id: receipt.transaction_id,
                reference: receipt.reference,
                status: receipt.status,
                amount_gnf: receipt.amount_gnf,
              },
            }}
          />
        </div>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-3 text-xs">
      <span className="text-muted-foreground">{label}</span>
      <span className={`text-right text-foreground font-medium ${mono ? "font-mono text-[11px]" : ""} break-all`}>{value}</span>
    </div>
  );
}

function statusTone(tone: import("@/lib/payments").StateTone) {
  if (tone === "pending") return "bg-secondary/15 text-secondary-foreground border-secondary/30";
  if (tone === "processing") return "bg-secondary/15 text-secondary-foreground border-secondary/30";
  if (tone === "failed") return "bg-destructive/10 text-destructive border-destructive/30";
  if (tone === "cancelled") return "bg-muted text-muted-foreground border-border";
  if (tone === "ok") return "bg-primary/10 text-primary border-primary/30";
  return "bg-muted text-muted-foreground border-border";
}
