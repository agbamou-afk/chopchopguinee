import { useEffect, useMemo, useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { QRCodeSVG } from "qrcode.react";
import { motion, AnimatePresence } from "framer-motion";
import {
  ArrowLeft,
  Lock,
  ShieldCheck,
  Receipt,
  Loader2,
  Store,
  CheckCircle2,
  Plus,
  Edit2,
  BadgeCheck,
  MapPin,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { formatGNF } from "@/lib/format";
import { buildChopPayPayload } from "@/lib/choppay";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { TrustCues, SecuredByChopPay } from "@/components/trust/TrustCues";
import { Seo } from "@/components/Seo";
import { toast } from "sonner";

type Merchant = {
  id: string;
  name: string;
  category: string | null;
  address: string | null;
  city: string | null;
  status: string;
  owner_user_id: string | null;
};

type Payment = {
  id: string;
  reference: string;
  amount_gnf: number;
  description: string | null;
  created_at: string;
  metadata: Record<string, unknown> | null;
};

export default function MerchantQR() {
  const { user, ready } = useAuth();
  const authLoading = !ready;
  const navigate = useNavigate();
  const [merchant, setMerchant] = useState<Merchant | null>(null);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [category, setCategory] = useState("Boutique");
  const [amount, setAmount] = useState<string>("");
  const [payments, setPayments] = useState<Payment[]>([]);
  const [lastSeenAt, setLastSeenAt] = useState<string | null>(null);
  const [pulse, setPulse] = useState(false);

  // Load my merchant
  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase
        .from("merchants")
        .select("id, name, category, address, city, status, owner_user_id")
        .eq("owner_user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!active) return;
      setMerchant((data as Merchant | null) ?? null);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [user, authLoading]);

  // Load recent payments + realtime
  useEffect(() => {
    if (!merchant) return;
    let active = true;

    Analytics.track("merchant.qr_viewed", { metadata: { merchant_id: merchant.id } });

    const fetchWalletId = async () => {
      const { data } = await supabase
        .from("wallets")
        .select("id")
        .eq("owner_user_id", merchant.owner_user_id!)
        .eq("party_type", "merchant")
        .maybeSingle();
      return data?.id ?? null;
    };

    const loadPayments = async () => {
      const wid = await fetchWalletId();
      if (!wid) {
        if (active) setPayments([]);
        return;
      }
      const { data } = await supabase
        .from("wallet_transactions")
        .select("id, reference, amount_gnf, description, created_at, metadata")
        .eq("to_wallet_id", wid)
        .eq("type", "payment")
        .order("created_at", { ascending: false })
        .limit(20);
      if (!active) return;
      const list = (data as Payment[] | null) ?? [];
      setPayments(list);
      // Detect new arrivals → pulse + toast
      if (lastSeenAt && list.length > 0 && list[0].created_at > lastSeenAt) {
        setPulse(true);
        try {
          toast.success("Paiement reçu", {
            description: `${formatGNF(list[0].amount_gnf)} via CHOPPay`,
          });
        } catch {}
        setTimeout(() => setPulse(false), 1800);
      }
      setLastSeenAt(list[0]?.created_at ?? new Date().toISOString());
    };

    loadPayments();
    const ch = supabase
      .channel(`merchant-pay-${merchant.id}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "wallet_transactions" },
        () => loadPayments(),
      )
      .subscribe();
    return () => {
      active = false;
      supabase.removeChannel(ch);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [merchant?.id]);

  const numericAmount = useMemo(() => {
    const n = Number(amount.replace(/\s/g, ""));
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : undefined;
  }, [amount]);

  const qrPayload = useMemo(() => {
    if (!merchant) return "";
    return buildChopPayPayload({
      merchantId: merchant.id,
      amount: numericAmount,
      merchantName: merchant.name,
    });
  }, [merchant, numericAmount]);

  const createMerchant = async () => {
    if (!user || !name.trim()) return;
    setCreating(true);
    const { data, error } = await supabase
      .from("merchants")
      .insert({
        owner_user_id: user.id,
        name: name.trim(),
        category,
        city: "Conakry",
        status: "active",
      })
      .select("id, name, category, address, city, status, owner_user_id")
      .single();
    setCreating(false);
    if (error) {
      toast.error("Création échouée", { description: error.message });
      return;
    }
    setMerchant(data as Merchant);
  };

  if (authLoading || loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!user) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-background px-6 text-center">
        <Store className="w-10 h-10 text-primary mb-3" />
        <p className="text-base font-semibold">Connectez-vous pour devenir marchand CHOP CHOP.</p>
        <Link to="/auth" className="mt-4">
          <Button className="gradient-primary">Se connecter</Button>
        </Link>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <Seo title="Marchand CHOPPay · CHOP CHOP" description="Recevez des paiements CHOPPay via QR." />
      <header className="px-4 py-3 flex items-center gap-3 border-b border-border/60">
        <button
          onClick={() => navigate(-1)}
          aria-label="Retour"
          className="p-1.5 rounded-lg hover:bg-muted"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="min-w-0">
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground leading-none">
            CHOPPay
          </p>
          <h1 className="text-base font-bold text-foreground leading-tight truncate">
            {merchant ? merchant.name : "Espace marchand"}
          </h1>
        </div>
      </header>

      <main className="max-w-md mx-auto px-4 pt-4 pb-28 space-y-5">
        {!merchant ? (
          <CreateMerchantForm
            name={name}
            setName={setName}
            category={category}
            setCategory={setCategory}
            creating={creating}
            onCreate={createMerchant}
          />
        ) : (
          <>
            {/* Merchant identity */}
            <div className="rounded-2xl border border-border/60 bg-card p-4 flex items-start gap-3 shadow-card">
              <div className="w-12 h-12 rounded-xl gradient-primary flex items-center justify-center shadow-soft shrink-0">
                <span className="text-sm font-bold text-primary-foreground tracking-wide">
                  {merchant.name
                    .trim()
                    .split(/\s+/)
                    .slice(0, 2)
                    .map((p) => p[0]?.toUpperCase() ?? "")
                    .join("") || "M"}
                </span>
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5">
                  <p className="font-semibold text-foreground truncate">{merchant.name}</p>
                  {merchant.status === "active" && (
                    <BadgeCheck className="w-4 h-4 text-primary shrink-0" aria-label="Marchand vérifié" />
                  )}
                </div>
                <p className="text-xs text-muted-foreground truncate">
                  {[merchant.category, merchant.city].filter(Boolean).join(" · ")}
                </p>
                {merchant.address && (
                  <p className="text-[11px] text-muted-foreground/80 truncate mt-0.5 inline-flex items-center gap-1">
                    <MapPin className="w-3 h-3" aria-hidden />
                    {merchant.address}
                  </p>
                )}
              </div>
              <span className="inline-flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full border border-success/30 bg-success/10 text-success">
                <CheckCircle2 className="w-3 h-3" />
                Actif
              </span>
            </div>

            {/* QR card */}
            <motion.div
              animate={pulse ? { scale: [1, 1.02, 1] } : { scale: 1 }}
              transition={{ duration: 0.6 }}
              className="relative rounded-3xl bg-card p-5 shadow-elevated border border-border/60 overflow-hidden"
            >
              <div
                aria-hidden
                className="absolute -top-16 -right-16 w-44 h-44 rounded-full bg-primary/8 blur-3xl"
              />
              <div className="relative">
                <div className="flex items-center justify-between mb-3">
                  <div className="inline-flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                    <Lock className="w-3 h-3 text-primary" />
                    Présenter pour encaisser
                  </div>
                  <span className="text-[10px] text-muted-foreground">CHOPPay</span>
                </div>

                <div className="mx-auto w-fit p-4 rounded-2xl bg-white shadow-soft ring-1 ring-border/40">
                  {qrPayload ? (
                    <QRCodeSVG value={qrPayload} size={208} level="M" includeMargin={false} />
                  ) : (
                    <div className="w-[208px] h-[208px] bg-muted animate-pulse rounded-md" />
                  )}
                </div>

                <div className="mt-4 grid gap-2">
                  <label className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
                    Montant (optionnel)
                  </label>
                  <div className="flex items-center gap-2">
                    <input
                      inputMode="numeric"
                      pattern="[0-9]*"
                      value={amount}
                      onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ""))}
                      placeholder="Saisie libre par le client"
                      className="flex-1 bg-muted/40 border border-border/60 rounded-xl px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/70 focus:outline-none focus:border-primary/40"
                    />
                    <span className="text-xs text-muted-foreground">GNF</span>
                  </div>
                  {numericAmount ? (
                    <p className="text-[11px] text-muted-foreground">
                      Le client verra <span className="font-semibold text-foreground">{formatGNF(numericAmount)}</span> à confirmer.
                    </p>
                  ) : (
                    <p className="text-[11px] text-muted-foreground">
                      Sans montant, le client saisit lui-même la somme.
                    </p>
                  )}
                </div>
              </div>
            </motion.div>

            <TrustCues
              cues={["choppay", "merchant_verified", "instant_credit"]}
              compact
              className="justify-center"
            />
            <div className="flex justify-center">
              <SecuredByChopPay />
            </div>

            {/* Recent payments */}
            <section>
              <div className="flex items-end justify-between mb-2">
                <h2 className="text-base font-bold text-foreground">Paiements récents</h2>
                <span className="text-[11px] text-muted-foreground">Mis à jour en direct</span>
              </div>
              <RecentPayments payments={payments} />
            </section>
          </>
        )}
      </main>
    </div>
  );
}

function CreateMerchantForm({
  name,
  setName,
  category,
  setCategory,
  creating,
  onCreate,
}: {
  name: string;
  setName: (v: string) => void;
  category: string;
  setCategory: (v: string) => void;
  creating: boolean;
  onCreate: () => void;
}) {
  return (
    <div className="rounded-3xl border border-border/60 bg-card p-5 shadow-card">
      <div className="w-12 h-12 rounded-2xl bg-primary/10 flex items-center justify-center mb-3">
        <Plus className="w-5 h-5 text-primary" />
      </div>
      <h2 className="text-lg font-bold text-foreground">Activez votre QR marchand</h2>
      <p className="text-sm text-muted-foreground mt-1">
        Recevez des paiements CHOPPay en GNF, créditez votre CHOPWallet automatiquement.
      </p>
      <div className="mt-4 space-y-3">
        <div>
          <label className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
            Nom du commerce
          </label>
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Ex: Boutique Kaba"
            className="mt-1"
          />
        </div>
        <div>
          <label className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
            Catégorie
          </label>
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="mt-1 w-full bg-muted/40 border border-border/60 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-primary/40"
          >
            <option>Boutique</option>
            <option>Restaurant</option>
            <option>Pharmacie</option>
            <option>Vendeur</option>
            <option>Service</option>
          </select>
        </div>
        <Button
          className="w-full h-11 gradient-primary"
          disabled={!name.trim() || creating}
          onClick={onCreate}
        >
          {creating ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Edit2 className="w-4 h-4 mr-2" />}
          Activer mon QR
        </Button>
        <p className="text-[11px] text-muted-foreground inline-flex items-center gap-1">
          <ShieldCheck className="w-3 h-3 text-success" /> Tous les paiements sont sécurisés par CHOPPay.
        </p>
      </div>
    </div>
  );
}

function RecentPayments({ payments }: { payments: Payment[] }) {
  if (payments.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border/60 bg-card/50 p-6 text-center">
        <Receipt className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
        <p className="text-sm font-medium text-foreground">Aucun paiement pour l'instant</p>
        <p className="text-xs text-muted-foreground mt-1">
          Présentez votre QR à un client pour recevoir un paiement.
        </p>
      </div>
    );
  }
  return (
    <ul className="space-y-2">
      <AnimatePresence initial={false}>
        {payments.map((p) => (
          <motion.li
            key={p.id}
            initial={{ opacity: 0, y: -6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="rounded-2xl bg-card border border-border/60 shadow-card p-3 flex items-center gap-3"
          >
            <div className="w-9 h-9 rounded-xl bg-success/10 flex items-center justify-center">
              <CheckCircle2 className="w-4 h-4 text-success" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground truncate">
                Paiement CHOPPay
              </p>
              <p className="text-[11px] text-muted-foreground truncate font-mono">
                {p.reference}
              </p>
            </div>
            <div className="text-right">
              <p className="text-sm font-semibold text-success">+ {formatGNF(p.amount_gnf)}</p>
              <p className="text-[11px] text-muted-foreground">{formatTime(p.created_at)}</p>
            </div>
          </motion.li>
        ))}
      </AnimatePresence>
    </ul>
  );
}

function formatTime(iso: string) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const time = d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
  return sameDay ? time : d.toLocaleString("fr-FR", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
}