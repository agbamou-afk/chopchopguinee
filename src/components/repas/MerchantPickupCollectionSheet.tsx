/**
 * R6 Retrait: the restaurant collects the customer-held one-time code before
 * the order can be completed. No one-click completion path remains.
 */
import { useState } from "react";
import { Loader2, ShieldCheck } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { confirmRepasPickupCollection, isRefusal, refusalMessage } from "@/lib/repas/custody";

interface Props {
  orderId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirmed?: () => void;
}

export function MerchantPickupCollectionSheet({ orderId, open, onOpenChange, onConfirmed }: Props) {
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [attemptsLeft, setAttemptsLeft] = useState<number | null>(null);
  const [locked, setLocked] = useState(false);

  const submit = async () => {
    if (locked) return;
    setBusy(true);
    try {
      const res = await confirmRepasPickupCollection(orderId, code);
      if (isRefusal(res)) {
        setAttemptsLeft(res.attempts_left);
        setLocked(res.locked);
        setCode("");
        toast.error(refusalMessage(res));
        return;
      }
      toast.success("Retrait confirmé");
      onConfirmed?.();
      onOpenChange(false);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl max-w-md mx-auto px-5 pb-8 pt-5">
        <SheetHeader className="text-left">
          <SheetTitle className="text-base font-bold">Confirmer le retrait</SheetTitle>
          <SheetDescription className="text-xs">
            Demandez au client son code de retrait à usage unique et saisissez-le au moment où vous
            lui remettez physiquement la commande.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-5 space-y-4">
          <Input
            inputMode="numeric"
            maxLength={6}
            value={code}
            disabled={locked}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="000000"
            className="h-12 text-center text-2xl tracking-[0.4em] font-bold tabular-nums"
          />
          {locked ? (
            <p className="text-xs font-semibold text-destructive">
              Code bloqué après 5 tentatives. Contactez le support.
            </p>
          ) : attemptsLeft !== null ? (
            <p className="text-xs font-semibold text-destructive">
              Code incorrect — {attemptsLeft} tentative{attemptsLeft > 1 ? "s" : ""} restante
              {attemptsLeft > 1 ? "s" : ""}.
            </p>
          ) : null}

          <Button
            className="w-full h-12"
            onClick={submit}
            disabled={busy || locked || code.length !== 6}
          >
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Client a récupéré"}
          </Button>
          <p className="inline-flex items-center gap-1 text-[10px] text-muted-foreground">
            <ShieldCheck className="w-3 h-3 text-primary" /> Vérification serveur — aucune
            complétion manuelle possible.
          </p>
        </div>
      </SheetContent>
    </Sheet>
  );
}
