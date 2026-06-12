import { useEffect, useMemo, useState } from "react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Loader2, ArrowLeft, CheckCircle2, AlertTriangle } from "lucide-react";
import { formatGNF } from "@/lib/format";
import {
  p2pLookupRecipient,
  p2pTransfer,
  type P2PRecipient,
  type P2PTransferResult,
} from "@/lib/wallet/p2p";
import { toast } from "sonner";

type Step = "phone" | "amount" | "confirm" | "success";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  available: number;
  onSent?: () => void;
}

export function SendMoneySheet({ open, onOpenChange, available, onSent }: Props) {
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("");
  const [busy, setBusy] = useState(false);
  const [recipient, setRecipient] = useState<P2PRecipient | null>(null);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [result, setResult] = useState<P2PTransferResult | null>(null);

  const idempotencyKey = useMemo(
    () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`,
    [open],
  );

  useEffect(() => {
    if (!open) {
      setStep("phone"); setPhone(""); setRecipient(null);
      setAmount(""); setNote(""); setResult(null); setBusy(false);
    }
  }, [open]);

  const lookup = async () => {
    setBusy(true);
    try {
      const r = await p2pLookupRecipient(phone);
      setRecipient(r); setStep("amount");
    } catch (e: any) {
      toast.error(e?.message ?? "Bénéficiaire introuvable");
    } finally {
      setBusy(false);
    }
  };

  const confirm = async () => {
    if (!recipient) return;
    const n = Number(amount);
    if (!Number.isFinite(n) || n <= 0) {
      toast.error("Montant invalide");
      return;
    }
    setBusy(true);
    try {
      const tx = await p2pTransfer({
        recipientUserId: recipient.user_id,
        amountGnf: n,
        note: note || null,
        idempotencyKey,
      });
      setResult(tx);
      setStep("success");
      onSent?.();
    } catch (e: any) {
      toast.error(e?.message ?? "Transfert impossible");
    } finally {
      setBusy(false);
    }
  };

  const amt = Number(amount);
  const amountOk = Number.isFinite(amt) && amt >= 1000 && amt <= 500000 && amt <= available;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl max-h-[92vh] overflow-y-auto">
        <SheetHeader className="text-left">
          <SheetTitle>Envoyer de l'argent</SheetTitle>
          <SheetDescription>
            Transfert instantané entre portefeuilles CHOP.
          </SheetDescription>
        </SheetHeader>

        {step === "phone" && (
          <div className="mt-4 space-y-3">
            <div>
              <Label htmlFor="p2p-phone">Numéro du bénéficiaire</Label>
              <Input
                id="p2p-phone" type="tel" inputMode="tel" autoFocus
                placeholder="6XX XX XX XX"
                value={phone} onChange={(e) => setPhone(e.target.value)}
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Indicatif +224. Le bénéficiaire doit avoir un compte CHOP CHOP.
              </p>
            </div>
            <Button className="w-full" disabled={busy || phone.length < 8} onClick={lookup}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Rechercher"}
            </Button>
          </div>
        )}

        {step === "amount" && recipient && (
          <div className="mt-4 space-y-3">
            <RecipientCard recipient={recipient} />
            <div>
              <Label htmlFor="p2p-amt">Montant (GNF)</Label>
              <Input
                id="p2p-amt" type="number" inputMode="numeric" min={1000} max={500000}
                value={amount} onChange={(e) => setAmount(e.target.value)}
                placeholder="Ex. 50 000"
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Solde disponible : <b>{formatGNF(available)}</b> · min 1 000 · max 500 000 / transfert
              </p>
            </div>
            <div>
              <Label htmlFor="p2p-note">Message (optionnel)</Label>
              <Textarea
                id="p2p-note" rows={2} maxLength={140}
                value={note} onChange={(e) => setNote(e.target.value)}
                placeholder="Ex. Remboursement déjeuner"
              />
            </div>
            <div className="flex gap-2">
              <Button variant="outline" className="flex-1" onClick={() => setStep("phone")}>
                <ArrowLeft className="w-4 h-4 mr-1" /> Retour
              </Button>
              <Button className="flex-1" disabled={!amountOk} onClick={() => setStep("confirm")}>
                Continuer
              </Button>
            </div>
          </div>
        )}

        {step === "confirm" && recipient && (
          <div className="mt-4 space-y-3">
            <RecipientCard recipient={recipient} />
            <div className="rounded-xl border border-border bg-muted/40 p-3 text-sm space-y-1">
              <Row label="Montant" value={formatGNF(Number(amount))} />
              {note && <Row label="Message" value={note} />}
            </div>
            <div className="flex items-start gap-2 rounded-xl bg-secondary/15 border border-secondary/30 p-3">
              <AlertTriangle className="w-4 h-4 text-secondary-foreground mt-0.5 shrink-0" />
              <p className="text-[11px] text-foreground/80">
                Vérifiez bien le bénéficiaire. Un transfert confirmé ne peut pas être annulé automatiquement.
              </p>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" className="flex-1" disabled={busy} onClick={() => setStep("amount")}>
                <ArrowLeft className="w-4 h-4 mr-1" /> Retour
              </Button>
              <Button className="flex-1" disabled={busy} onClick={confirm}>
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Confirmer l'envoi"}
              </Button>
            </div>
          </div>
        )}

        {step === "success" && recipient && result && (
          <div className="mt-4 space-y-3 text-center">
            <div className="mx-auto w-14 h-14 rounded-full bg-success/15 flex items-center justify-center">
              <CheckCircle2 className="w-7 h-7 text-success" />
            </div>
            <h3 className="text-lg font-bold">Transfert envoyé</h3>
            <p className="text-sm text-muted-foreground">
              {formatGNF(result.amount_gnf)} envoyé à <b>{recipient.display_name}</b> ({recipient.masked_phone}).
            </p>
            <div className="rounded-xl border border-border bg-muted/40 p-3 text-[11px] text-left space-y-0.5">
              <Row label="Référence" value={result.reference} />
              <Row label="Date" value={new Date(result.created_at).toLocaleString("fr-FR")} />
            </div>
            <Button className="w-full" onClick={() => onOpenChange(false)}>Fermer</Button>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}

function RecipientCard({ recipient }: { recipient: P2PRecipient }) {
  return (
    <div className="rounded-xl border border-primary/30 bg-primary/5 p-3">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Bénéficiaire</p>
      <p className="text-sm font-semibold">{recipient.display_name}</p>
      <p className="text-xs text-muted-foreground">{recipient.masked_phone}</p>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium text-foreground truncate">{value}</span>
    </div>
  );
}