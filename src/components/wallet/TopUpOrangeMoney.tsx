import { useEffect, useMemo, useState } from "react";
import { motion } from "framer-motion";
import { Loader2, Copy, Check, Smartphone, Clock, ShieldCheck, ArrowLeft, AlertTriangle, KeyRound, Hourglass } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";
import { ensureOnlineForFinancialAction } from "@/contexts/AppEnvContext";

type TopupRow = {
  id: string;
  reference: string;
  amount_gnf: number;
  status: string;
  expires_at: string;
  customer_om_code_submitted_at?: string | null;
};

type ReceivingAccount = {
  id: string;
  provider: string;
  label: string;
  phone_e164: string;
  public_instructions: string | null;
};

const QUICK_AMOUNTS = [10000, 25000, 50000, 100000, 250000, 500000];

export function TopUpOrangeMoney({ onClose }: { onClose: () => void }) {
  const [step, setStep] = useState<"amount" | "instructions">("amount");
  const [amount, setAmount] = useState<number>(50000);
  const [creating, setCreating] = useState(false);
  const [topup, setTopup] = useState<TopupRow | null>(null);
  const [accounts, setAccounts] = useState<ReceivingAccount[]>([]);
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(null);
  const [accountsLoading, setAccountsLoading] = useState(true);
  const [copied, setCopied] = useState<"ref" | "msisdn" | null>(null);
  const [now, setNow] = useState(Date.now());
  const [omCode, setOmCode] = useState("");
  const [submittingCode, setSubmittingCode] = useState(false);

  // Load admin-configured active Orange Money receiving accounts.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data, error } = await supabase.rpc("get_active_payment_receiving_accounts");
      if (cancelled) return;
      if (error) {
        setAccounts([]);
      } else {
        const rows = ((data ?? []) as ReceivingAccount[]).filter(
          (r) => r.provider === "orange_money",
        );
        setAccounts(rows);
        if (rows.length > 0) setSelectedAccountId(rows[0].id);
      }
      setAccountsLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const activeAccount = useMemo(
    () => accounts.find((a) => a.id === selectedAccountId) ?? accounts[0] ?? null,
    [accounts, selectedAccountId],
  );

  // Live status — subscribe to the topup row
  // Live status — financial realtime is disabled for security, so poll on a
  // gentle interval (via sanitized SECURITY DEFINER RPC) and on tab
  // visibility changes until the request reaches a terminal state.
  useEffect(() => {
    if (!topup) return;
    const terminal = ["credited", "expired", "failed", "cancelled"].includes(topup.status);
    if (terminal) return;
    let cancelled = false;
    const refetch = async () => {
      const { data } = await supabase.rpc("get_my_topup_om_status", { p_topup_id: topup.id });
      const row = Array.isArray(data) ? data[0] : null;
      if (!cancelled && row) {
        setTopup((prev) => prev ? { ...prev, ...row } : prev);
      }
    };
    const interval = setInterval(() => {
      if (typeof document === "undefined" || document.visibilityState === "visible") {
        void refetch();
      }
    }, 6000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void refetch();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      cancelled = true;
      clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [topup?.id, topup?.status]);

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
    if (!activeAccount) {
      toast.error("Recharge Orange Money indisponible pour le moment.");
      return;
    }
    if (!ensureOnlineForFinancialAction()) {
      toast.error("Connexion indisponible. Réessayez quand vous serez en ligne.");
      return;
    }
    setCreating(true);
    const { data, error } = await supabase.rpc("wallet_topup_om_create", {
      p_amount_gnf: amount,
      p_receiving_account_id: activeAccount.id,
    });
    setCreating(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setTopup(data as unknown as TopupRow);
    setOmCode("");
    setStep("instructions");
  };

  const submitOmCode = async () => {
    if (!topup) return;
    const code = omCode.trim();
    if (code.length < 4) {
      toast.error("Code Orange Money trop court");
      return;
    }
    if (!ensureOnlineForFinancialAction()) {
      toast.error("Connexion indisponible. Réessayez quand vous serez en ligne.");
      return;
    }
    setSubmittingCode(true);
    const { data, error } = await supabase.rpc("submit_customer_om_code", {
      p_topup_request_id: topup.id,
      p_om_code: code,
    });
    setSubmittingCode(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    const result = (data ?? {}) as { status?: string; reason?: string };
    if (result.status === "needs_review") {
      toast.warning("Code reçu — vérification nécessaire");
    } else {
      toast.success("Code envoyé · en attente de confirmation");
    }
    // Refresh status
    const { data: row } = await supabase.rpc("get_my_topup_om_status", { p_topup_id: topup.id });
    const r = Array.isArray(row) ? row[0] : null;
    if (r) setTopup((prev) => prev ? { ...prev, ...r } : prev);
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
                  Compte marchand CHOPCHOP
                </p>
                <button
                  onClick={() =>
                    activeAccount && copy(activeAccount.phone_e164.replace(/\s/g, ""), "msisdn")
                  }
                  className="mt-1 w-full flex items-center justify-between gap-3 rounded-xl bg-muted/50 px-3 py-2 hover:bg-muted transition"
                >
                  <span className="flex items-center gap-2 font-mono font-semibold">
                    <Smartphone className="w-4 h-4 text-primary" />
                    {activeAccount?.phone_e164 ?? "—"}
                  </span>
                  {copied === "msisdn" ? (
                    <Check className="w-4 h-4 text-success" />
                  ) : (
                    <Copy className="w-4 h-4 text-muted-foreground" />
                  )}
                </button>
                {activeAccount?.label && (
                  <p className="text-[11px] text-muted-foreground mt-1">{activeAccount.label}</p>
                )}
                {activeAccount?.public_instructions && (
                  <p className="text-[11px] text-muted-foreground mt-1 whitespace-pre-line">
                    {activeAccount.public_instructions}
                  </p>
                )}
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
                  5. Gardez votre preuve de paiement (SMS / code OM).
                </li>
                <li>
                  6. Un opérateur CHOPCHOP vérifie votre paiement, puis votre portefeuille est{" "}
                  <span className="font-semibold text-foreground">crédité après vérification</span>.
                  Temps de traitement estimé : quelques minutes à quelques heures.
                </li>
              </ol>
            </div>

            {/* Customer OM confirmation code submission */}
            {!topup.customer_om_code_submitted_at ? (
              <div className="rounded-3xl bg-card border border-border p-4 space-y-2 shadow-card">
                <div className="flex items-center gap-2">
                  <KeyRound className="w-4 h-4 text-primary" />
                  <p className="text-sm font-semibold">Collez votre code Orange Money</p>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  Après l'envoi, OM vous donne un code de confirmation. Collez-le ici pour accélérer la vérification.
                </p>
                <Input
                  value={omCode}
                  onChange={(e) => setOmCode(e.target.value)}
                  placeholder="ex. ABC123XYZ"
                  maxLength={40}
                  className="font-mono"
                />
                <Button onClick={submitOmCode} disabled={submittingCode || omCode.trim().length < 4} className="w-full">
                  {submittingCode ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
                  Envoyer le code
                </Button>
              </div>
            ) : (
              <div className="rounded-2xl bg-muted/40 border border-border/60 p-3 flex items-center gap-2">
                {review ? (
                  <>
                    <ShieldCheck className="w-4 h-4 text-secondary-foreground shrink-0" />
                    <p className="text-xs text-muted-foreground">
                      Recharge en vérification. Le support CHOPCHOP va examiner la transaction.
                    </p>
                  </>
                ) : (
                  <>
                    <Hourglass className="w-4 h-4 text-primary shrink-0" />
                    <p className="text-xs text-muted-foreground">
                      Code reçu. Nous attendons la confirmation CHOPCHOP.
                    </p>
                  </>
                )}
              </div>
            )}
          </>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {!accountsLoading && accounts.length === 0 && (
        <div className="rounded-2xl bg-destructive/10 border border-destructive/30 p-3 flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 text-destructive shrink-0 mt-0.5" />
          <p className="text-xs text-foreground">
            Recharge Orange Money indisponible pour le moment. Réessayez plus tard.
          </p>
        </div>
      )}
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

      <Button
        onClick={create}
        disabled={creating || amount < 1000 || !activeAccount || accountsLoading}
        className="w-full h-12"
      >
        {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créer la demande de recharge"}
      </Button>

      <p className="text-[11px] text-muted-foreground text-center">
        Vous recevrez les instructions de paiement Orange Money à l'étape suivante.
      </p>
    </div>
  );
}