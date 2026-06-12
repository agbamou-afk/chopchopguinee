import { useMemo, useState } from "react";
import { Loader2, Search, Wallet as WalletIcon, CheckCircle2, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { GuineaPhoneInput } from "@/components/ui/guinea-phone-input";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/format";
import {
  agentLookupCustomer,
  agentCashInCustomer,
  type AgentCustomerPreview,
  type AgentCashInResult,
} from "@/lib/wallet/serviceAgent";

type Step = "lookup" | "amount" | "success";

/**
 * Phase 9 — Service Agent cash-in panel. Only mounted when the merchant
 * store has service_agent_status='approved'. Never writes to wallets from
 * the client; both lookup and credit run through SECURITY DEFINER RPCs.
 */
export function ServiceAgentCashInPanel() {
  const [step, setStep] = useState<Step>("lookup");
  const [phone, setPhone] = useState("");
  const [looking, setLooking] = useState(false);
  const [customer, setCustomer] = useState<AgentCustomerPreview | null>(null);

  const [amountText, setAmountText] = useState("");
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [receipt, setReceipt] = useState<AgentCashInResult | null>(null);

  const amount = useMemo(() => {
    const n = parseInt(amountText.replace(/\D/g, ""), 10);
    return Number.isFinite(n) ? n : 0;
  }, [amountText]);

  const reset = () => {
    setStep("lookup");
    setPhone("");
    setCustomer(null);
    setAmountText("");
    setNote("");
    setReceipt(null);
  };

  const handleLookup = async () => {
    if (phone.length < 8) {
      toast({ title: "Numéro incomplet", description: "Entrez un numéro guinéen." });
      return;
    }
    setLooking(true);
    try {
      const c = await agentLookupCustomer(phone);
      setCustomer(c);
      setStep("amount");
    } catch (e: any) {
      toast({ title: "Client introuvable", description: e?.message ?? "Recherche impossible." });
    } finally {
      setLooking(false);
    }
  };

  const handleConfirm = async () => {
    if (!customer) return;
    if (amount < 1000) {
      toast({ title: "Montant invalide", description: "Minimum : 1 000 GNF." });
      return;
    }
    setSubmitting(true);
    try {
      const idem = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
      const r = await agentCashInCustomer({
        customerUserId: customer.customer_user_id,
        amountGnf: amount,
        note: note.trim() || null,
        idempotencyKey: idem,
      });
      setReceipt(r);
      setStep("success");
    } catch (e: any) {
      toast({ title: "Limite dépassée", description: e?.message ?? "Recharge impossible." });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="bg-card rounded-2xl border border-border/60 p-4 space-y-3">
      <div className="flex items-center gap-2">
        <div className="w-9 h-9 rounded-xl bg-emerald-500/15 text-emerald-700 flex items-center justify-center">
          <WalletIcon className="w-4 h-4" />
        </div>
        <div className="flex-1">
          <h3 className="font-bold text-foreground text-sm">Recharger un client</h3>
          <p className="text-[11px] text-muted-foreground">
            Encaissez le cash, puis créditez le CHOP Wallet du client.
          </p>
        </div>
      </div>

      {step === "lookup" && (
        <div className="space-y-3">
          <div className="space-y-1">
            <Label htmlFor="agent-cust-phone" className="text-xs">Numéro du client</Label>
            <GuineaPhoneInput
              id="agent-cust-phone"
              value={phone}
              onChange={setPhone}
              disabled={looking}
            />
          </div>
          <Button onClick={handleLookup} disabled={looking || phone.length < 8} className="w-full">
            {looking ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Search className="w-4 h-4 mr-2" />}
            Rechercher le client
          </Button>
          <p className="text-[11px] text-muted-foreground text-center">
            Retrait client bientôt disponible.
          </p>
        </div>
      )}

      {step === "amount" && customer && (
        <div className="space-y-3">
          <div className="rounded-xl bg-muted/40 border border-border/60 p-3">
            <p className="text-xs text-muted-foreground">Client</p>
            <p className="text-sm font-bold text-foreground">{customer.display_name}</p>
            <p className="text-[11px] text-muted-foreground">{customer.masked_phone}</p>
          </div>
          <div className="space-y-1">
            <Label htmlFor="agent-amt" className="text-xs">Montant reçu en espèces (GNF)</Label>
            <Input
              id="agent-amt"
              inputMode="numeric"
              placeholder="50 000"
              value={amountText}
              onChange={(e) => setAmountText(e.target.value)}
              disabled={submitting}
            />
            <p className="text-[10px] text-muted-foreground">
              Min 1 000 · Max 1 000 000 par recharge · Plafond jour 5 000 000.
            </p>
          </div>
          <div className="space-y-1">
            <Label htmlFor="agent-note" className="text-xs">Référence (optionnel)</Label>
            <Input
              id="agent-note"
              maxLength={80}
              placeholder="Reçu n°… ou note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={submitting}
            />
          </div>
          <div className="flex gap-2">
            <Button
              variant="outline"
              className="flex-1"
              onClick={() => { setStep("lookup"); setCustomer(null); }}
              disabled={submitting}
            >
              <ArrowLeft className="w-4 h-4 mr-1" /> Retour
            </Button>
            <Button
              className="flex-1 gradient-primary"
              onClick={handleConfirm}
              disabled={submitting || amount < 1000}
            >
              {submitting ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
              Confirmer la recharge
            </Button>
          </div>
        </div>
      )}

      {step === "success" && receipt && customer && (
        <div className="space-y-3 text-center py-2">
          <div className="w-12 h-12 mx-auto rounded-full bg-emerald-500/15 text-emerald-700 flex items-center justify-center">
            <CheckCircle2 className="w-6 h-6" />
          </div>
          <p className="text-sm font-bold text-foreground">Recharge effectuée</p>
          <p className="text-xs text-muted-foreground">
            {customer.display_name} · {customer.masked_phone}
          </p>
          <p className="text-2xl font-extrabold text-foreground">{formatGNF(receipt.amount_gnf)} GNF</p>
          <p className="text-[10px] text-muted-foreground break-all">{receipt.reference}</p>
          <Button variant="outline" className="w-full" onClick={reset}>
            Nouvelle recharge
          </Button>
        </div>
      )}
    </div>
  );
}