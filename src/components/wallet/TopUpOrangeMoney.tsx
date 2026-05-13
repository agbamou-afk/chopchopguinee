import { useEffect, useMemo, useState } from "react";
import { motion } from "framer-motion";
import { Loader2, Copy, Check, Smartphone, Clock, ShieldCheck, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";

type TopupRow = {
  id: string;
  reference: string;
  amount_gnf: number;
  status: string;
  expires_at: string;
  transaction_id: string | null;
};

const QUICK_AMOUNTS = [10000, 25000, 50000, 100000, 250000, 500000];

export function TopUpOrangeMoney({ onClose }: { onClose: () => void }) {
  const [step, setStep] = useState<"amount" | "instructions">("amount");
  const [amount, setAmount] = useState<number>(50000);
  const [creating, setCreating] = useState(false);
  const [topup, setTopup] = useState<TopupRow | null>(null);
  const [merchant, setMerchant] = useState<string>("+224 620 00 00 00");
  const [copied, setCopied] = useState<"ref" | "msisdn" | null>(null);
  const [now, setNow] = useState(Date.now());

  // Load merchant MSISDN from app_settings.orange_money
  useEffect(() => {
    supabase
      .from("app_settings")
      .select("value")
      .eq("key", "orange_money")
      .maybeSingle()
      .then(({ data }) => {
        const v = (data?.value ?? {}) as { merchant_msisdn?: string };
        if (v.merchant_msisdn && v.merchant_msisdn.trim()) setMerchant(v.merchant_msisdn);
      });
  }, []);

  // Live status — subscribe to the topup row
  useEffect(() => {
    if (!topup) return;
    const ch = supabase
      .channel(`topup-${topup.id}-${Math.random().toString(36).slice(2)}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "topup_requests", filter: `id=eq.${topup.id}` },
        (payload) => setTopup(payload.new as TopupRow),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [topup?.id]);

  // Countdown timer
  useEffect(() => {
    if (!topup) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [topup]);

  const create = async () => {
    if (amount < 1000) {
      toast.error("Montant minimum: 1 000 GNF");
      return;
    }
    setCreating(true);
    const { data, error } = await supabase.rpc("wallet_topup_om_create", { p_amount_gnf: amount });
    setCreating(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setTopup(data as unknown as TopupRow);
    setStep("instructions");
  };

  const copy = async (text: string, kind: "ref" | "msisdn") => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(kind);
      setTimeout(() => setCopied(null), 1500);
    } catch {
      toast.error("Impossible de copier");
    }
  };

  const remaining = useMemo(() => {
    if (!topup) return "";
    const ms = new Date(topup.expires_at).getTime() - now;
    if (ms <= 0) return "expirée";
    const h = Math.floor(ms / 3600000);
    const m = Math.floor((ms % 3600000) / 60000);
    return h > 0 ? `${h}h ${m}m` : `${m} min`;
  }, [topup, now]);

  if (step === "instructions" && topup) {
    const credited = topup.status === "credited";
    const expired = topup.status === "expired" || topup.status === "failed";
    const review = topup.status === "needs_review";

    return (
      <div className="space-y-4">
        <button
          onClick={() => {
            setTopup(null);
            setStep("amount");
          }}
          className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="w-4 h-4" /> Nouvelle recharge
        </button>

        {credited ? (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="rounded-3xl bg-success/10 border border-success/30 p-6 text-center"
          >
            <div className="w-14 h-14 mx-auto rounded-full bg-success flex items-center justify-center mb-3">
              <Check className="w-7 h-7 text-success-foreground" />
            </div>
            <h3 className="text-lg font-bold text-foreground">Recharge confirmée</h3>
            <p className="text-sm text-muted-foreground mt-1">
              +{formatGNF(topup.amount_gnf)} crédités sur votre portefeuille.
            </p>
            <Button className="mt-4 w-full" onClick={onClose}>
              Fermer
            </Button>
          </motion.div>
        ) : expired ? (
          <div className="rounded-3xl bg-destructive/10 border border-destructive/30 p-5">
            <p className="font-semibold text-destructive">Demande expirée</p>
            <p className="text-sm text-muted-foreground mt-1">
              Créez une nouvelle demande pour réessayer.
            </p>
          </div>
        ) : (
          <>
            <div className="rounded-3xl gradient-wallet text-primary-foreground p-5">
              <p className="text-[11px] uppercase tracking-wider opacity-90">Montant à envoyer</p>
              <p className="text-3xl font-extrabold mt-1">{formatGNF(topup.amount_gnf)}</p>
              <div className="mt-3 inline-flex items-center gap-1.5 glass-surface rounded-full px-2.5 py-1">
                <Clock className="w-3.5 h-3.5" />
                <span className="text-[11px] font-semibold">Expire dans {remaining}</span>
              </div>
            </div>

            <div className="rounded-3xl bg-card border border-border p-4 space-y-3 shadow-card">
              <div>
                <p className="text-[11px] uppercase tracking-wider text-muted-foreground">
                  Compte marchand CHOP CHOP
                </p>
                <button
                  onClick={() => copy(merchant.replace(/\s/g, ""), "msisdn")}
                  className="mt-1 w-full flex items-center justify-between gap-3 rounded-xl bg-muted/50 px-3 py-2 hover:bg-muted transition"
                >
                  <span className="flex items-center gap-2 font-mono font-semibold">
                    <Smartphone className="w-4 h-4 text-primary" />
                    {merchant}
                  </span>
                  {copied === "msisdn" ? (
                    <Check className="w-4 h-4 text-success" />
                  ) : (
                    <Copy className="w-4 h-4 text-muted-foreground" />
                  )}
                </button>
              </div>

              <div>
                <p className="text-[11px] uppercase tracking-wider text-muted-foreground">
                  Référence (à inclure si possible)
                </p>
                <button
                  onClick={() => copy(topup.reference, "ref")}
                  className="mt-1 w-full flex items-center justify-between gap-3 rounded-xl bg-primary/10 px-3 py-2 hover:bg-primary/15 transition"
                >
                  <span className="font-mono font-bold text-primary">{topup.reference}</span>
                  {copied === "ref" ? (
                    <Check className="w-4 h-4 text-success" />
                  ) : (
                    <Copy className="w-4 h-4 text-primary" />
                  )}
                </button>
              </div>

              <ol className="text-xs text-muted-foreground space-y-1.5 pt-2 border-t border-border">
                <li>1. Composez <span className="font-mono font-semibold">#144#</span> sur Orange Money.</li>
                <li>2. Choisissez « Paiement marchand ».</li>
                <li>
                  3. Envoyez{" "}
                  <span className="font-semibold text-foreground">{formatGNF(topup.amount_gnf)}</span>{" "}
                  au numéro ci-dessus.
                </li>
                <li>4. Indiquez la référence dans le motif si possible.</li>
                <li>
                  5. Votre portefeuille sera{" "}
                  <span className="font-semibold text-foreground">crédité automatiquement</span>{" "}
                  après vérification.
                </li>
              </ol>
            </div>

            <div className="rounded-2xl bg-muted/40 border border-border/60 p-3 flex items-center gap-2">
              {review ? (
                <>
                  <ShieldCheck className="w-4 h-4 text-secondary-foreground shrink-0" />
                  <p className="text-xs text-muted-foreground">
                    Paiement reçu — en cours de vérification par le support CHOP CHOP.
                  </p>
                </>
              ) : (
                <>
                  <Loader2 className="w-4 h-4 animate-spin text-primary shrink-0" />
                  <p className="text-xs text-muted-foreground">
                    En attente du paiement Orange Money…
                  </p>
                </>
              )}
            </div>
          </>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <p className="text-sm text-muted-foreground">Montant de la recharge</p>
        <div className="mt-2 flex items-baseline gap-2">
          <Input
            type="number"
            inputMode="numeric"
            min={1000}
            step={1000}
            value={amount || ""}
            onChange={(e) => setAmount(Number(e.target.value) || 0)}
            className="text-2xl font-extrabold h-14"
          />
          <span className="text-lg font-semibold text-muted-foreground">GNF</span>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2">
        {QUICK_AMOUNTS.map((v) => (
          <button
            key={v}
            onClick={() => setAmount(v)}
            className={`rounded-xl px-2 py-2.5 text-sm font-semibold border transition ${
              amount === v
                ? "bg-primary text-primary-foreground border-primary"
                : "bg-card border-border hover:bg-muted"
            }`}
          >
            {formatGNF(v)}
          </button>
        ))}
      </div>

      <Button onClick={create} disabled={creating || amount < 1000} className="w-full h-12">
        {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créer la demande de recharge"}
      </Button>

      <p className="text-[11px] text-muted-foreground text-center">
        Vous recevrez les instructions de paiement Orange Money à l'étape suivante.
      </p>
    </div>
  );
}