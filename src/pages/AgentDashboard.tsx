import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import {
  Loader2,
  LogOut,
  Plus,
  Wallet as WalletIcon,
  XCircle,
  History,
} from "lucide-react";
import logo from "@/assets/logo.png";

const fmt = (n: number) => new Intl.NumberFormat("fr-GN").format(n);

type AgentInfo = {
  business_name: string;
  location: string | null;
  daily_limit_gnf: number;
  prepaid_float_gnf: number;
  balance_gnf: number;
};

type TopupRow = {
  id: string;
  reference: string;
  amount_gnf: number;
  status: string;
  created_at: string;
  client_user_id: string;
};

export default function AgentDashboard() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [agent, setAgent] = useState<AgentInfo | null>(null);
  const [topups, setTopups] = useState<TopupRow[]>([]);

  const load = async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      navigate("/auth");
      return;
    }
    const uid = session.user.id;
    const { data: ap } = await supabase
      .from("agent_profiles")
      .select("business_name, location, daily_limit_gnf, prepaid_float_gnf, status")
      .eq("user_id", uid)
      .maybeSingle();
    if (!ap || ap.status !== "active") {
      setError("Votre compte n'est pas un agent CHOP CHOP actif. Contactez l'administrateur.");
      setLoading(false);
      return;
    }
    const { data: w } = await supabase
      .from("wallets")
      .select("balance_gnf")
      .eq("owner_user_id", uid)
      .eq("party_type", "agent")
      .maybeSingle();
    setAgent({
      business_name: ap.business_name,
      location: ap.location,
      daily_limit_gnf: ap.daily_limit_gnf,
      prepaid_float_gnf: ap.prepaid_float_gnf,
      balance_gnf: w?.balance_gnf ?? 0,
    });
    const { data: t } = await supabase
      .from("topup_requests")
      .select("id, reference, amount_gnf, status, created_at, client_user_id")
      .eq("agent_user_id", uid)
      .order("created_at", { ascending: false })
      .limit(20);
    setTopups((t as TopupRow[]) ?? []);
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, []);

  const signOut = async () => {
    await supabase.auth.signOut();
    navigate("/auth");
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background px-4">
        <div className="max-w-sm w-full bg-card rounded-3xl p-6 shadow-elevated text-center">
          <XCircle className="w-12 h-12 text-destructive mx-auto mb-3" />
          <h1 className="text-lg font-bold text-foreground mb-2">Accès refusé</h1>
          <p className="text-sm text-muted-foreground mb-4">{error}</p>
          <div className="flex gap-2">
            <Button variant="outline" className="flex-1" onClick={signOut}>
              Se déconnecter
            </Button>
            <Link to="/" className="flex-1">
              <Button variant="outline" className="w-full">Retour</Button>
            </Link>
          </div>
        </div>
      </div>
    );
  }

  const statusColor = (s: string) =>
    s === "confirmed"
      ? "text-success bg-success/10"
      : s === "pending"
      ? "text-primary bg-primary/10"
      : "text-muted-foreground bg-muted";

  return (
    <div className="min-h-screen bg-background pb-24">
      <header className="gradient-primary p-4 pb-10 rounded-b-3xl">
        <div className="max-w-md mx-auto flex items-center gap-3">
          <img src={logo} alt="CHOP CHOP" className="h-12 w-auto object-contain" />
          <div className="flex-1 min-w-0">
            <h1 className="font-bold text-primary-foreground truncate">
              {agent!.business_name}
            </h1>
            <p className="text-xs text-primary-foreground/80 truncate">
              {agent!.location ?? "Agent CHOP CHOP"}
            </p>
          </div>
          <Button variant="secondary" size="sm" onClick={signOut}>
            <LogOut className="w-4 h-4 mr-1" /> Quitter
          </Button>
        </div>
      </header>

      <main className="max-w-md mx-auto px-4 -mt-6 pt-2 pb-6 space-y-5">
        <div className="bg-card rounded-3xl p-5 shadow-elevated">
          <div className="flex items-center gap-2 text-xs text-muted-foreground uppercase tracking-wide">
            <WalletIcon className="w-4 h-4" />
            Float disponible
          </div>
          <p className="text-3xl font-bold text-foreground mt-2">
            {fmt(agent!.balance_gnf)} <span className="text-lg text-muted-foreground">GNF</span>
          </p>
          <div className="grid grid-cols-2 gap-3 mt-4 text-xs">
            <div className="bg-muted/40 rounded-xl p-3">
              <p className="text-muted-foreground">Limite jour</p>
              <p className="font-semibold text-foreground">
                {fmt(agent!.daily_limit_gnf)} GNF
              </p>
            </div>
            <div className="bg-muted/40 rounded-xl p-3">
              <p className="text-muted-foreground">Float chargé</p>
              <p className="font-semibold text-foreground">
                {fmt(agent!.prepaid_float_gnf)} GNF
              </p>
            </div>
          </div>
        </div>

        <Link to="/agent/topup">
          <Button className="w-full h-14 gradient-primary text-base">
            <Plus className="w-5 h-5 mr-2" />
            Nouvelle recharge client
          </Button>
        </Link>

        <div className="bg-card rounded-2xl shadow-card overflow-hidden">
          <div className="px-5 py-3 border-b flex items-center gap-2">
            <History className="w-4 h-4 text-muted-foreground" />
            <h2 className="font-semibold text-foreground text-sm">Recharges récentes</h2>
          </div>
          {topups.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-8">
              Aucune recharge pour le moment.
            </p>
          ) : (
            <ul className="divide-y">
              {topups.map((t) => (
                <li key={t.id} className="px-5 py-3 flex items-center justify-between">
                  <div className="min-w-0">
                    <p className="font-medium text-sm text-foreground">
                      {fmt(t.amount_gnf)} GNF
                    </p>
                    <p className="text-[11px] text-muted-foreground truncate">
                      {t.reference} · {new Date(t.created_at).toLocaleString("fr-FR")}
                    </p>
                  </div>
                  <span
                    className={`text-[10px] uppercase font-semibold px-2 py-1 rounded-full ${statusColor(
                      t.status,
                    )}`}
                  >
                    {t.status}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </main>
    </div>
  );
}