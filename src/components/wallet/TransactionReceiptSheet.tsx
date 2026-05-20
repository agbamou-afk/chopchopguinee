import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { ShieldCheck, Receipt } from "lucide-react";
import { formatGNF } from "@/lib/format";
import type { WalletTransaction } from "@/hooks/useWallet";
import { txLabel, txStatusCopy, type TxDirection } from "@/lib/wallet/labels";

interface Props {
  tx: WalletTransaction | null;
  direction: TxDirection;
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

/**
 * Calm, lightweight payment receipt. Mirrors physical receipt mental model
 * without banking jargon. Linked-entity CTA appears only when meaningful.
 */
export function TransactionReceiptSheet({ tx, direction, open, onOpenChange }: Props) {
  if (!tx) return null;
  const status = txStatusCopy(tx.status);
  const ref = tx.related_entity ?? null;
  const linkedCta = ref ? linkedCtaFor(ref) : null;
  const dateStr = new Date(tx.created_at).toLocaleString("fr-FR", {
    day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit",
  });

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

        <div className="mt-5 space-y-4">
          <div className="text-center">
            <p className="text-xs text-muted-foreground">{txLabel(tx, direction)}</p>
            <p className={`text-3xl font-extrabold tabular-nums mt-1 ${direction === "in" ? "text-[hsl(160_55%_28%)]" : "text-foreground"}`}>
              {direction === "in" ? "+" : "-"}{formatGNF(Math.abs(tx.amount_gnf))}
            </p>
            {status && (
              <span className={`inline-block mt-2 text-[11px] font-semibold px-2 py-0.5 rounded-full border ${statusTone(status.tone)}`}>
                {status.label}
              </span>
            )}
          </div>

          <div className="bg-card rounded-2xl border border-border/60 p-4 space-y-2.5 shadow-card">
            <Row label="Date" value={dateStr} />
            <Row label="Méthode" value="CHOPWallet" />
            {tx.description && <Row label="Détail" value={tx.description} />}
            <Row label="Référence" value={tx.reference} mono />
          </div>

          <div className="flex items-center gap-2 text-[11px] text-muted-foreground justify-center">
            <ShieldCheck className="w-3.5 h-3.5 text-primary" />
            Transaction sécurisée par CHOPPay
          </div>

          {linkedCta && (
            <Button variant="outline" className="w-full" onClick={() => onOpenChange(false)}>
              {linkedCta}
            </Button>
          )}
        </div>
      </SheetContent>
    </Sheet>
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

function statusTone(tone: "pending" | "failed" | "cancelled" | "ok") {
  if (tone === "pending") return "bg-secondary/15 text-secondary-foreground border-secondary/30";
  if (tone === "failed") return "bg-destructive/10 text-destructive border-destructive/30";
  return "bg-muted text-muted-foreground border-border";
}

function linkedCtaFor(ref: string): string | null {
  const r = ref.toLowerCase();
  if (r.startsWith("food_") || r.includes("repas")) return "Voir la commande";
  if (r.startsWith("listing:") || r.includes("marketplace") || r.includes("marche")) return "Voir l'article";
  if (r.startsWith("mission:") || r.includes("mission")) return "Voir la mission";
  if (r.startsWith("ride:") || r.includes("ride")) return "Voir la course";
  return null;
}