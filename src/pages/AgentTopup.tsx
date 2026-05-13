import { useEffect, useState } from "react";
import { formatGNF } from "@/lib/format";
import { Link, useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  Loader2,
  Phone,
  Wallet as WalletIcon,
  CheckCircle2,
  XCircle,
  ArrowLeft,
  ScanLine,
} from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSlot,
} from "@/components/ui/input-otp";
import { QrScanner } from "@/components/scanner/QrScanner";
import logo from "@/assets/logo.png";

type Step = "lookup" | "amount" | "confirm" | "done";

type AgentInfo = {
  business_name: string;
  prepaid_float: number;
};

const fmt = (n: number) => formatGNF(n);

export default function AgentTopup() {
  const navigate = useNavigate();
  const [authChecked, setAuthChecked] = useState(false);
  const [agent, setAgent] = useState<AgentInfo | null>(null);
  const [agentError, setAgentError] = useState<string | null>(null);

  const [step, setStep] = useState<Step>("lookup");
  const [phoneInput, setPhoneInput] = useState("");
  const [scanOpen, setScanOpen] = useState(false);
  const [client, setClient] = useState<{ user_id: string; full_name: string | null; phone: string | null } | null>(null);

  const [amount, setAmount] = useState("");
  const [topupId, setTopupId] = useState<string | null>(null);
  const [topupRef, setTopupRef] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const init = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        navigate("/auth");
        return;
      }
      const uid = session.user.id;
      const { data: ap } = await supabase
        .from("agent_profiles")
        .select("business_name, status")
        .eq("user_id", uid)
        .maybeSingle();
      if (!ap || ap.status !== "active") {
        setAgentError("Votre compte n'est pas un agent CHOP CHOP actif.");
      } else {
        const { data: w } = await supabase
          .from("wallets")
          .select("balance_gnf")
          .eq("owner_user_id", uid)
          .eq("party_type", "agent")
          .maybeSingle();
        setAgent({
          business_name: ap.business_name,
          prepaid_float: w?.balance_gnf ?? 0,
        });
      }
      setAuthChecked(true);
    };
    init();
  }, [navigate]);

  const lookupByPhone = async () => {
    if (!phoneInput.trim()) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("find_user_by_phone", {
      p_phone: phoneInput.trim(),
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    const row = (data as { user_id: string; full_name: string | null }[] | null)?.[0];
    if (!row) {
      toast.error("Client introuvable");
      return;
    }
    setClient({ user_id: row.user_id, full_name: row.full_name, phone: phoneInput.trim() });
    setStep("amount");
  };

  const handleScan = (raw: string) => {
    setScanOpen(false);
    try {
      const parsed = JSON.parse(raw);
      if (parsed?.t === "chopchop-user" && typeof parsed.id === "string") {
        setClient({ user_id: parsed.id, full_name: null, phone: null });
        setStep("amount");
        return;
      }
    } catch {
      // not json
    }
    toast.error("QR invalide");
  };

  const createTopup = async () => {
    if (!client) return;
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      toast.error("Montant invalide");
      return;
    }
    if (agent && amt > agent.prepaid_float) {
      toast.error("Float insuffisant");
      return;
    }
    setBusy(true);
    const { data, error } = await supabase.rpc("wallet_topup_create", {
      p_client_user_id: client.user_id,
      p_amount_gnf: amt,
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    const row = data as { id: string; reference: string };
    setTopupId(row.id);
    setTopupRef(row.reference);
    setStep("confirm");
    toast.success("Demande envoyée. Demandez le code au client.");
  };

  const confirmTopup = async () => {
    if (!topupId || code.length !== 6) {
      toast.error("Entrez le code à 6 chiffres");
      return;
    }
    setBusy(true);
    const { error } = await supabase.rpc("wallet_topup_confirm", {
      p_topup_id: topupId,
      p_code: code,
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Recharge réussie");
    setStep("done");
    // refresh agent float
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      const { data: w } = await supabase
        .from("wallets")
        .select("balance_gnf")
        .eq("owner_user_id", session.user.id)
        .eq("party_type", "agent")
        .maybeSingle();
      if (w && agent) setAgent({ ...agent, prepaid_float: w.balance_gnf });
    }
  };

  const cancelTopup = async () => {
    if (!topupId) return;
    await supabase.rpc("wallet_topup_cancel", {
      p_topup_id: topupId,
      p_reason: "Cancelled by agent",
    });
    reset();
  };

  const reset = () => {
    setClient(null);
    setAmount("");
    setTopupId(null);
    setTopupRef(null);
    setCode("");
    setStep("lookup");
    setPhoneInput("");
  };

  if (!authChecked) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin" />
      </div>
    );
  }

  if (agentError) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background px-4">
        <div className="max-w-sm w-full bg-card rounded-3xl p-6 shadow-elevated text-center">
          <XCircle className="w-12 h-12 text-destructive mx-auto mb-3" />
          <h1 className="text-lg font-bold text-foreground mb-2">Accès refusé</h1>
          <p className="text-sm text-muted-foreground mb-4">{agentError}</p>
          <Link to="/">
            <Button variant="outline" className="w-full">
              Retour
            </Button>
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <header className="gradient-primary p-4 pb-10 rounded-b-3xl">
        <div className="max-w-md mx-auto flex items-center gap-3">
          <Link
            to="/agent"
            className="p-1 hover:bg-white/10 rounded-lg text-primary-foreground"
            aria-label="Retour"
          >
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <img src={logo} alt="CHOP CHOP" className="h-10 w-auto object-contain" />
          <div className="flex-1 min-w-0">
            <h1 className="font-bold text-primary-foreground leading-tight">Recharge agent</h1>
            <p className="text-xs text-primary-foreground/80 truncate">
              {agent?.business_name}
            </p>
          </div>
          <div className="text-right">
            <p className="text-[10px] text-primary-foreground/80 uppercase">Float</p>
            <p className="font-bold text-primary-foreground text-sm">
              {fmt(agent?.prepaid_float ?? 0)} GNF
            </p>
          </div>
        </div>
      </header>

      <main className="max-w-md mx-auto px-4 -mt-6 pt-2 pb-6">
        <AnimatePresence mode="wait">
          {step === "lookup" && (
            <motion.div
              key="lookup"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="space-y-4"
            >
              <div className="bg-card rounded-2xl p-5 shadow-card">
                <Label htmlFor="phone" className="text-sm">Numéro du client</Label>
                <div className="flex gap-2 mt-2">
                  <div className="flex items-center gap-2 flex-1 border rounded-md px-3">
                    <Phone className="w-4 h-4 text-muted-foreground" />
                    <Input
                      id="phone"
                      value={phoneInput}
                      onChange={(e) => setPhoneInput(e.target.value)}
                      placeholder="+224 6XX XXX XXX"
                      className="border-0 px-0 focus-visible:ring-0"
                    />
                  </div>
                  <Button onClick={lookupByPhone} disabled={busy} className="gradient-primary">
                    {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Chercher"}
                  </Button>
                </div>
              </div>

              <div className="text-center text-xs text-muted-foreground">— ou —</div>

              <Button
                variant="outline"
                onClick={() => setScanOpen(true)}
                className="w-full h-12"
              >
                <ScanLine className="w-5 h-5 mr-2" />
                Scanner le QR du client
              </Button>
            </motion.div>
          )}

          {step === "amount" && client && (
            <motion.div
              key="amount"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="space-y-4"
            >
              <div className="bg-card rounded-2xl p-5 shadow-card">
                <p className="text-xs text-muted-foreground">Client</p>
                <p className="font-semibold text-foreground">
                  {client.full_name ?? "Client CHOP CHOP"}
                </p>
                {client.phone && (
                  <p className="text-sm text-muted-foreground">{client.phone}</p>
                )}
                <p className="text-[10px] text-muted-foreground mt-1 truncate">
                  ID: {client.user_id}
                </p>
              </div>

              <div className="bg-card rounded-2xl p-5 shadow-card">
                <Label htmlFor="amount" className="text-sm">Montant (GNF)</Label>
                <Input
                  id="amount"
                  type="number"
                  inputMode="numeric"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="100000"
                  className="mt-2 text-2xl h-14 text-center font-bold"
                />
                <div className="flex gap-2 mt-3 flex-wrap">
                  {[20000, 50000, 100000, 200000, 500000].map((n) => (
                    <button
                      key={n}
                      onClick={() => setAmount(String(n))}
                      className="px-3 py-1 text-xs bg-muted hover:bg-muted/80 rounded-full"
                    >
                      {fmt(n)}
                    </button>
                  ))}
                </div>
              </div>

              <div className="flex gap-2">
                <Button variant="outline" onClick={reset} className="flex-1">
                  Annuler
                </Button>
                <Button
                  onClick={createTopup}
                  disabled={busy || !amount}
                  className="flex-1 gradient-primary"
                >
                  {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Demander code"}
                </Button>
              </div>
            </motion.div>
          )}

          {step === "confirm" && client && (
            <motion.div
              key="confirm"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="space-y-4"
            >
              <div className="bg-primary/10 border border-primary/20 rounded-2xl p-5">
                <WalletIcon className="w-6 h-6 text-primary mb-2" />
                <p className="text-sm text-foreground">
                  Demande de recharge envoyée à{" "}
                  <strong>{client.full_name ?? client.phone ?? "le client"}</strong>.
                </p>
                <p className="text-2xl font-bold text-foreground my-2">
                  {fmt(Number(amount))} GNF
                </p>
                <p className="text-xs text-muted-foreground">
                  Le client voit un code à 6 chiffres dans son app. Demandez-le-lui{" "}
                  <strong>après</strong> avoir reçu l'argent.
                </p>
                {topupRef && (
                  <p className="text-[10px] text-muted-foreground mt-2">Réf: {topupRef}</p>
                )}
              </div>

              <div className="bg-card rounded-2xl p-5 shadow-card">
                <Label className="text-sm mb-3 block">Code du client</Label>
                <div className="flex justify-center">
                  <InputOTP maxLength={6} value={code} onChange={setCode}>
                    <InputOTPGroup>
                      {[0, 1, 2, 3, 4, 5].map((i) => (
                        <InputOTPSlot key={i} index={i} />
                      ))}
                    </InputOTPGroup>
                  </InputOTP>
                </div>
              </div>

              <div className="flex gap-2">
                <Button variant="outline" onClick={cancelTopup} className="flex-1">
                  Annuler
                </Button>
                <Button
                  onClick={confirmTopup}
                  disabled={busy || code.length !== 6}
                  className="flex-1 gradient-primary"
                >
                  {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Confirmer"}
                </Button>
              </div>
            </motion.div>
          )}

          {step === "done" && (
            <motion.div
              key="done"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className="bg-card rounded-2xl p-8 shadow-card text-center"
            >
              <CheckCircle2 className="w-14 h-14 text-success mx-auto mb-3" />
              <h2 className="text-lg font-bold text-foreground mb-1">Recharge réussie</h2>
              <p className="text-sm text-muted-foreground mb-4">
                {fmt(Number(amount))} GNF crédités au client
              </p>
              <Button onClick={reset} className="w-full gradient-primary">
                Nouvelle recharge
              </Button>
            </motion.div>
          )}
        </AnimatePresence>
      </main>

      {scanOpen && (
        <QrScanner
          onClose={() => setScanOpen(false)}
          onResult={handleScan}
          title="Scanner le QR du client"
          subtitle="Positionnez le QR du client dans le cadre"
        />
      )}
    </div>
  );
}