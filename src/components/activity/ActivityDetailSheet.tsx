import { useEffect } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Separator } from "@/components/ui/separator";
import { Button } from "@/components/ui/button";
import { ChevronRight, ShieldCheck, LifeBuoy, Receipt } from "lucide-react";
import { formatGNF } from "@/lib/format";
import type { ActivityItem } from "@/lib/activity/types";
import { formatActivityTime } from "@/lib/activity/types";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { useNavigate } from "react-router-dom";

interface ActivityDetailSheetProps {
  item: ActivityItem | null;
  onClose: () => void;
}

function Row({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between py-2">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className={`text-sm font-medium text-foreground ${mono ? "tabular-nums" : ""}`}>{value}</span>
    </div>
  );
}

export function ActivityDetailSheet({ item, onClose }: ActivityDetailSheetProps) {
  const navigate = useNavigate();
  const open = !!item;

  useEffect(() => {
    if (item) {
      Analytics.track("receipt.opened", {
        metadata: { kind: item.kind, reference: item.reference, status: item.status },
      });
    }
  }, [item]);

  if (!item) {
    return (
      <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
        <SheetContent side="bottom" className="rounded-t-3xl" />
      </Sheet>
    );
  }

  const positive = item.amount !== undefined && item.amount > 0;
  const amountStr = item.amount !== undefined ? `${positive ? "+" : ""}${formatGNF(item.amount)}` : "—";

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="bottom" className="rounded-t-3xl px-5 pb-8 pt-5 max-h-[88vh] overflow-y-auto">
        <SheetHeader className="text-left">
          <SheetTitle className="text-base font-bold">{item.title}</SheetTitle>
          {item.subtitle && (
            <SheetDescription className="text-xs">{item.subtitle}</SheetDescription>
          )}
        </SheetHeader>

        <div className="mt-5 rounded-2xl bg-muted/40 px-4 py-4 flex items-center justify-between">
          <div>
            <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Montant</p>
            <p className={`text-2xl font-extrabold tabular-nums ${positive ? "text-success" : "text-foreground"}`}>
              {amountStr}
            </p>
          </div>
          {item.badge === "choppay" && (
            <span className="inline-flex items-center gap-1 px-2 py-1 rounded-full text-[11px] font-semibold text-primary bg-primary/10">
              <ShieldCheck className="w-3 h-3" /> CHOPPay
            </span>
          )}
        </div>

        <div className="mt-4 divide-y divide-border/60">
          <Row label="Statut" value={item.status === "completed" ? "Confirmé" : item.status} />
          <Row label="Date" value={formatActivityTime(item.occurredAt)} />
          {item.reference && <Row label="Référence" value={item.reference} mono />}
        </div>

        <Separator className="my-5" />

        <div className="space-y-2">
          {item.kind === "ride" && item.entityId && (
            <Button
              variant="outline"
              className="w-full justify-between h-11 rounded-2xl"
              onClick={() => {
                onClose();
                // Future: navigate to a dedicated /ride/:id receipt page.
              }}
            >
              <span className="inline-flex items-center gap-2">
                <Receipt className="w-4 h-4" /> Voir le reçu de la course
              </span>
              <ChevronRight className="w-4 h-4 text-muted-foreground" />
            </Button>
          )}
          {(item.kind === "merchant_payment" || item.kind === "topup" || item.kind === "transfer_in" || item.kind === "transfer_out") && (
            <Button
              variant="outline"
              className="w-full justify-between h-11 rounded-2xl"
              onClick={() => {
                onClose();
              }}
            >
              <span className="inline-flex items-center gap-2">
                <Receipt className="w-4 h-4" /> Voir dans CHOPWallet
              </span>
              <ChevronRight className="w-4 h-4 text-muted-foreground" />
            </Button>
          )}
          <Button
            variant="ghost"
            className="w-full justify-between h-11 rounded-2xl text-muted-foreground"
            onClick={() => {
              onClose();
              navigate("/help");
            }}
          >
            <span className="inline-flex items-center gap-2">
              <LifeBuoy className="w-4 h-4" /> Besoin d'aide ?
            </span>
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}