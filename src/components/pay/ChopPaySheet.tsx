import { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  X,
  ShieldCheck,
  Loader2,
  CheckCircle2,
  AlertCircle,
  Lock,
  Wallet,
  Receipt,
  Store,
  Radio,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useWallet } from "@/hooks/useWallet";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { TrustCues, SecuredByChopPay } from "@/components/trust/TrustCues";
import type { ChopPayPayload } from "@/lib/choppay";
import { toast } from "sonner";

type Merchant = {
  id: string;
  name: string;
  category: string | null;
  address: string | null;
  city: string | null;
  status: string;
};

interface Props {
  open: boolean;
  payload: ChopPayPayload | null;
  onClose: () => void;
}

type Step = "loading" | "confirm" | "processing" | "success" | "error";

/**
 * CHOPPay payment sheet — opens after a successful merchant-QR scan.
 * Calm, single-purpose surface: merchant identity + amount + one CTA.
 */
export function ChopPaySheet({ open, payload, onClose }: Props) {
  const { available, refresh, userId } = useWallet("client");
  const [merchant, setMerchant] = useState<Merchant | null>(null);
  const [amountInput, setAmountInput] = useState<string>("");
  const [step, setStep] = useState<Step>("loading");
  const [error, setError] = useState<string | null>(null);
  const [receipt, setReceipt] = useState<{ ref: string; tx_id: string; at: string } | null>(null);

  const amountFromQr = payload?.amount ?? 0;
  const fixedAmount = amountFromQr > 0;

  const amount = useMemo(() => {
    if (fixedAmount) return amountFromQr;
    const n = Number(amountInput.replace(/\s/g, ""));
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  }, [amountInput, amountFromQr, fixedAmount]);

  // Reset on open / payload change
  useEffect(() => {
    if (!open || !payload) return;
    setMerchant(null);
    setReceipt(null);
    setError(null);
    setAmountInput("");
    setStep("loading");

    let active = true;
    Analytics.track("qr.payment_sheet_opened", {
      metadata: { merchant_id: payload.merchantId, prefilled: !!payload.amount },
    });
    Analytics.track("ride.trust_message_viewed", { metadata: { surface: "choppay_sheet" } });

    (async () => {
      const { data, error } = await supabase
        .from("merchants")
        .select("id, name, category, address, city, status")
        .eq("id", payload.merchantId)
        .maybeSingle();
      if (!active) return;
      if (error || !data) {
        setError("Marchand introuvable ou inactif.");
        setStep("error");
        return;
      }
      if (data.status !== "active") {
        setError("Ce marchand n'est pas actif.");
        setStep("error");
        return;
      }
      setMerchant(data as Merchant);
      setStep("confirm");
    })();

    return () => {
      active = false;
    };
  }, [open, payload]);

  const insufficient = amount > 0 && amount > available;
  const canPay = step === "confirm" && !!merchant && amount > 0 && !insufficient && !!userId;

  const onCancel = () => {
    if (step === "processing") return;
    if (step === "confirm" && merchant) {
      Analytics.track("qr.payment_cancelled", {
        metadata: { merchant_id: merchant.id, amount },
      });
    }
    onClose();
  };

  const onPay = async () => {
    if (!canPay || !merchant) return;
    setStep("processing");
    setError(null);
    const { data, error } = await supabase.rpc("wallet_pay_merchant", {
      p_merchant_id: merchant.id,
      p_amount_gnf: amount,
      p_description: `Paiement CHOPPay · ${merchant.name}`,
    });
    if (error || !data) {
      const msg = mapPayError(error?.message);
      setError(msg);
      setStep("error");
      Analytics.track("qr.payment_failed", {
        metadata: { merchant_id: merchant.id, amount, code: error?.message ?? "unknown" },
      });
      return;
    }
    const tx = data as { id: string; reference: string; created_at: string };
    setReceipt({ ref: tx.reference, tx_id: tx.id, at: tx.created_at });
    setStep("success");
    refresh();
    Analytics.track("qr.payment_confirmed", {
      metadata: { merchant_id: merchant.id, amount, tx_id: tx.id },
    });
    Analytics.track("receipt.qr_payment_viewed", {
      metadata: { merchant_id: merchant.id, amount },
    });
    try {
      toast.success("Paiement confirmé", { description: merchant.name });
    } catch {}
  };

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-[70] bg-black/55 flex items-end sm:items-center justify-center p-0 sm:p-4"
          onClick={onCancel}
        >
          <motion.div
            initial={{ y: 60, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 60, opacity: 0 }}
            transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
            onClick={(e) => e.stopPropagation()}
            className="bg-card w-full max-w-md rounded-t-3xl sm:rounded-3xl shadow-elevated overflow-hidden"
          >
            {/* Header */}
            <div className="relative px-5 pt-5 pb-3 border-b border-border/50">
              <div className="flex items-center justify-between">
                <div className="inline-flex items-center gap-2">
                  <div className="w-8 h-8 rounded-xl bg-primary/10 flex items-center justify-center">
                    <Lock className="w-4 h-4 text-primary" aria-hidden />
                  </div>
                  <div>
                    <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground leading-none">
                      CHOPPay
                    </p>
                    <p className="text-sm font-semibold text-foreground leading-tight">
                      Paiement marchand
                    </p>
                  </div>
                </div>
                <button
                  onClick={onCancel}
                  disabled={step === "processing"}
                  className="p-1.5 rounded-lg hover:bg-muted disabled:opacity-40"
                  aria-label="Fermer"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            </div>

            {step === "loading" && (
              <div className="px-6 py-12 flex flex-col items-center text-center">
                <Loader2 className="w-6 h-6 animate-spin text-muted-foreground mb-3" />
                <p className="text-sm text-muted-foreground">Vérification du marchand…</p>
              </div>
            )}

            {step === "error" && (
              <div className="px-6 py-8 flex flex-col items-center text-center">
                <div className="w-12 h-12 rounded-2xl bg-destructive/10 flex items-center justify-center mb-3">
                  <AlertCircle className="w-6 h-6 text-destructive" />
                </div>
                <p className="text-base font-semibold text-foreground">Paiement impossible</p>
                <p className="text-sm text-muted-foreground mt-1 max-w-[20rem]">
                  {error ?? "Une erreur est survenue. Réessayez."}
                </p>
                <Button className="mt-5 w-full h-11" variant="outline" onClick={onClose}>
                  Fermer
                </Button>
              </div>
            )}

            {(step === "confirm" || step === "processing") && merchant && (
              <div className="px-5 pt-5 pb-6 space-y-5">
                {/* Merchant identity */}
                <div className="rounded-2xl border border-border/60 bg-muted/30 p-4 flex items-start gap-3">
                  <div className="w-11 h-11 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                    <Store className="w-5 h-5 text-primary" aria-hidden />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-base font-semibold text-foreground leading-tight truncate">
                      {merchant.name}
                    </p>
                    <p className="text-xs text-muted-foreground truncate">
                      {[merchant.category, merchant.address ?? merchant.city]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                  </div>
                </div>

                {/* Amount */}
                <div className="text-center">
                  <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
                    Montant à payer
                  </p>
                  {fixedAmount ? (
                    <p className="mt-2 text-4xl font-bold text-foreground tracking-tight">
                      {formatGNF(amount)}
                    </p>
                  ) : (
                    <div className="mt-2">
                      <input
                        autoFocus
                        inputMode="numeric"
                        pattern="[0-9]*"
                        value={amountInput}
                        onChange={(e) =>
                          setAmountInput(e.target.value.replace(/[^0-9]/g, ""))
                        }
                        placeholder="0"
                        className="w-full bg-transparent text-center text-4xl font-bold tracking-tight text-foreground placeholder:text-muted-foreground/40 focus:outline-none"
                      />
                      <p className="text-xs text-muted-foreground">GNF</p>
                    </div>
                  )}
                </div>

                {/* Wallet line */}
                <div className="rounded-2xl border border-border/60 bg-card p-3 flex items-center gap-3">
                  <div className="w-9 h-9 rounded-xl bg-secondary/20 flex items-center justify-center">
                    <Wallet className="w-4 h-4 text-foreground" aria-hidden />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-[12px] font-medium text-foreground leading-tight">
                      CHOPWallet
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      Solde disponible · {formatGNF(available)}
                    </p>
                  </div>
                  {insufficient && (
                    <span className="inline-flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full border border-destructive/30 bg-destructive/10 text-destructive">
                      Solde insuffisant
                    </span>
                  )}
                </div>

                {/* Trust cues */}
                <TrustCues cues={["choppay", "verified", "live"]} compact className="justify-center" />

                {/* CTAs */}
                <div className="space-y-2 pt-1">
                  <Button
                    className="w-full h-12 gradient-primary text-primary-foreground"
                    disabled={!canPay || step === "processing"}
                    onClick={onPay}
                  >
                    {step === "processing" ? (
                      <>
                        <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                        Paiement en cours…
                      </>
                    ) : (
                      <>
                        <Lock className="w-4 h-4 mr-2" />
                        Payer avec CHOPPay
                      </>
                    )}
                  </Button>
                  <Button
                    variant="ghost"
                    className="w-full h-10"
                    onClick={onCancel}
                    disabled={step === "processing"}
                  >
                    Annuler
                  </Button>
                </div>
              </div>
            )}

            {step === "success" && merchant && receipt && (
              <ChopPaySuccess
                merchant={merchant}
                amount={amount}
                reference={receipt.ref}
                at={receipt.at}
                onClose={onClose}
              />
            )}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function ChopPaySuccess({
  merchant,
  amount,
  reference,
  at,
  onClose,
}: {
  merchant: Merchant;
  amount: number;
  reference: string;
  at: string;
  onClose: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="px-6 pt-6 pb-7 flex flex-col items-center text-center"
    >
      <motion.div
        initial={{ scale: 0.6, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
        className="w-16 h-16 rounded-full bg-success/10 ring-4 ring-success/15 flex items-center justify-center mb-3"
      >
        <CheckCircle2 className="w-8 h-8 text-success" />
      </motion.div>
      <p className="text-lg font-bold text-foreground">Paiement confirmé</p>
      <p className="text-xs text-muted-foreground mt-0.5">{merchant.name}</p>

      <p className="mt-5 text-3xl font-bold text-foreground tracking-tight">
        − {formatGNF(amount)}
      </p>
      <p className="text-[11px] text-muted-foreground mt-1">Débité de votre CHOPWallet</p>

      <div className="w-full mt-5 rounded-2xl border border-border/60 bg-muted/30 p-3 text-left space-y-1.5">
        <ReceiptRow icon={Receipt} label="Référence" value={reference} mono />
        <ReceiptRow icon={Store} label="Marchand" value={merchant.name} />
        <ReceiptRow icon={Radio} label="Date" value={formatReceiptDate(at)} />
        <ReceiptRow icon={ShieldCheck} label="Statut" value="Confirmé · CHOPPay" tone="success" />
      </div>

      <div className="mt-4">
        <SecuredByChopPay />
      </div>

      <Button className="w-full h-12 mt-5 gradient-primary" onClick={onClose}>
        Terminé
      </Button>
    </motion.div>
  );
}

function ReceiptRow({
  icon: Icon,
  label,
  value,
  mono,
  tone,
}: {
  icon: typeof Receipt;
  label: string;
  value: string;
  mono?: boolean;
  tone?: "success";
}) {
  return (
    <div className="flex items-center gap-2 text-[12px]">
      <Icon className="w-3.5 h-3.5 text-muted-foreground" aria-hidden />
      <span className="text-muted-foreground">{label}</span>
      <span
        className={`ml-auto font-semibold ${
          tone === "success" ? "text-success" : "text-foreground"
        } ${mono ? "font-mono tracking-tight" : ""}`}
      >
        {value}
      </span>
    </div>
  );
}

function formatReceiptDate(iso: string) {
  const d = new Date(iso);
  return d.toLocaleString("fr-FR", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function mapPayError(code?: string): string {
  if (!code) return "Une erreur est survenue. Réessayez.";
  if (/insufficient_funds/i.test(code)) return "Solde CHOPWallet insuffisant.";
  if (/wallet_not_found/i.test(code)) return "Activez votre CHOPWallet pour payer.";
  if (/merchant_not_found/i.test(code)) return "Marchand introuvable ou inactif.";
  if (/merchant_misconfigured/i.test(code)) return "Marchand non configuré.";
  if (/cannot_pay_self/i.test(code)) return "Vous ne pouvez pas vous payer vous-même.";
  if (/not_authenticated/i.test(code)) return "Connectez-vous pour payer.";
  if (/invalid_amount/i.test(code)) return "Montant invalide.";
  return "Paiement refusé. Réessayez.";
}