import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { Loader2, LogOut, ShieldCheck, Bike, Car, KeyRound, Store, Plus, Wallet } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter } from "@/components/ui/dialog";

interface Fare {
  id: string;
  ride_type: string;
  base_price: number;
  price_per_km: number;
  currency: string;
  updated_at: string;
}

interface AgentRow {
  id: string;
  user_id: string;
  business_name: string;
  location: string | null;
  status: string;
  daily_limit_gnf: number;
  commission_rate: number;
  prepaid_float_gnf: number;
  profile?: { full_name: string | null; phone: string | null } | null;
}

export default function Admin() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);
  const [userId, setUserId] = useState<string | null>(null);
  const [email, setEmail] = useState<string>("");
  const [fares, setFares] = useState<Fare[]>([]);
  const [saving, setSaving] = useState<string | null>(null);
  const [claiming, setClaiming] = useState(false);
  const [agents, setAgents] = useState<AgentRow[]>([]);
  const [loadingAgents, setLoadingAgents] = useState(false);

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      if (!session) navigate("/auth", { replace: true });
    });
    (async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        navigate("/auth", { replace: true });
        return;
      }
      setUserId(session.user.id);
      setEmail(session.user.email ?? "");
      const { data: roles } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", session.user.id);
      const admin = !!roles?.some((r) => r.role === "admin");
      setIsAdmin(admin);
      if (admin) {
        const { data: f } = await supabase.from("fare_settings").select("*").order("ride_type");
        setFares(f ?? []);
        await loadAgents();
      }
      setLoading(false);
    })();
    return () => { sub.subscription.unsubscribe(); };
  }, [navigate]);

  const loadAgents = async () => {
    setLoadingAgents(true);
    const { data: ags } = await supabase
      .from("agent_profiles")
      .select("*")
      .order("created_at", { ascending: false });
    const list = (ags ?? []) as AgentRow[];
    if (list.length) {
      const ids = list.map((a) => a.user_id);
      const { data: profs } = await supabase
        .from("profiles")
        .select("user_id, full_name, phone")
        .in("user_id", ids);
      const map = new Map((profs ?? []).map((p) => [p.user_id, p]));
      list.forEach((a) => { a.profile = map.get(a.user_id) as any; });
    }
    setAgents(list);
    setLoadingAgents(false);
  };

  const claimAdmin = async () => {
    if (!userId) return;
    setClaiming(true);
    const { data, error } = await supabase.rpc("claim_first_admin");
    setClaiming(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
    } else if (data === false) {
      toast({ title: "Refusé", description: "Un administrateur existe déjà." });
    } else {
      toast({ title: "Vous êtes administrateur" });
      window.location.reload();
    }
  };

  const updateFare = async (fare: Fare, patch: Partial<Fare>) => {
    setSaving(fare.id);
    const { error } = await supabase
      .from("fare_settings")
      .update({ base_price: patch.base_price ?? fare.base_price, price_per_km: patch.price_per_km ?? fare.price_per_km })
      .eq("id", fare.id);
    setSaving(null);
    if (error) {
      toast({ title: "Erreur", description: error.message });
    } else {
      toast({ title: "Tarif mis à jour", description: fare.ride_type });
      const { data: f } = await supabase.from("fare_settings").select("*").order("ride_type");
      setFares(f ?? []);
    }
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    navigate("/auth", { replace: true });
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background px-4">
        <div className="max-w-sm w-full bg-card rounded-3xl shadow-elevated p-6 text-center">
          <div className="w-14 h-14 rounded-2xl bg-muted flex items-center justify-center mx-auto mb-3">
            <KeyRound className="w-7 h-7 text-muted-foreground" />
          </div>
          <h2 className="text-lg font-bold mb-1">Accès restreint</h2>
          <p className="text-sm text-muted-foreground mb-4">
            Connecté en tant que <strong>{email}</strong>, mais ce compte n'a pas le rôle administrateur.
          </p>
          <Button onClick={claimAdmin} disabled={claiming} className="w-full gradient-primary mb-2">
            {claiming ? <Loader2 className="w-4 h-4 animate-spin" /> : "Devenir administrateur (premier compte)"}
          </Button>
          <Button variant="outline" onClick={signOut} className="w-full">
            <LogOut className="w-4 h-4 mr-2" /> Se déconnecter
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <header className="gradient-primary p-4 pb-8 rounded-b-3xl">
        <div className="flex items-center justify-between max-w-3xl mx-auto">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-white/20 flex items-center justify-center">
              <ShieldCheck className="w-5 h-5 text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-lg font-bold text-primary-foreground">Administration Choper</h1>
              <p className="text-xs text-primary-foreground/80">{email}</p>
            </div>
          </div>
          <Button variant="secondary" size="sm" onClick={signOut}>
            <LogOut className="w-4 h-4 mr-1" /> Quitter
          </Button>
        </div>
      </header>

      <main className="max-w-3xl mx-auto p-4 -mt-4 space-y-4">
        <Tabs defaultValue="fares" className="w-full">
          <TabsList className="grid grid-cols-2 w-full">
            <TabsTrigger value="fares">Tarifs</TabsTrigger>
            <TabsTrigger value="agents">Agents</TabsTrigger>
          </TabsList>

          <TabsContent value="fares">
        <section className="bg-card rounded-2xl shadow-card p-5">
          <h2 className="text-base font-semibold mb-1">Grille tarifaire</h2>
          <p className="text-sm text-muted-foreground mb-4">
            Définissez le prix de base et le prix au kilomètre pour chaque type de course. Les changements s'appliquent immédiatement aux estimations clients.
          </p>

          <div className="space-y-4">
            {fares.map((f) => {
              const Icon = f.ride_type === "moto" ? Bike : Car;
              return (
                <FareRow
                  key={f.id}
                  fare={f}
                  Icon={Icon}
                  saving={saving === f.id}
                  onSave={(patch) => updateFare(f, patch)}
                />
              );
            })}
          </div>
        </section>
          </TabsContent>

          <TabsContent value="agents">
            <AgentsPanel
              agents={agents}
              loading={loadingAgents}
              onChanged={loadAgents}
            />
          </TabsContent>
        </Tabs>
      </main>
    </div>
  );
}

function AgentsPanel({ agents, loading, onChanged }: { agents: AgentRow[]; loading: boolean; onChanged: () => void }) {
  const [open, setOpen] = useState(false);
  const [phone, setPhone] = useState("");
  const [business, setBusiness] = useState("");
  const [location, setLocation] = useState("");
  const [dailyLimit, setDailyLimit] = useState("5000000");
  const [commission, setCommission] = useState("0.01");
  const [submitting, setSubmitting] = useState(false);

  const fmt = (n: number) => new Intl.NumberFormat("fr-FR").format(n) + " GNF";

  const create = async () => {
    setSubmitting(true);
    const { error } = await supabase.rpc("admin_create_agent", {
      p_phone: phone.trim(),
      p_business_name: business.trim(),
      p_location: location.trim() || null,
      p_daily_limit_gnf: Number(dailyLimit) || 0,
      p_commission_rate: Number(commission) || 0,
    });
    setSubmitting(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    toast({ title: "Agent créé" });
    setOpen(false);
    setPhone(""); setBusiness(""); setLocation("");
    onChanged();
  };

  return (
    <section className="bg-card rounded-2xl shadow-card p-5">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-base font-semibold">Agents de recharge</h2>
          <p className="text-xs text-muted-foreground">Gérer les points de cash-in et leur float prépayé.</p>
        </div>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="gradient-primary">
              <Plus className="w-4 h-4 mr-1" /> Agent
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader><DialogTitle>Onboarder un agent</DialogTitle></DialogHeader>
            <div className="space-y-3">
              <div>
                <Label className="text-xs">Téléphone du compte (existant)</Label>
                <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+224..." />
              </div>
              <div>
                <Label className="text-xs">Nom du commerce</Label>
                <Input value={business} onChange={(e) => setBusiness(e.target.value)} />
              </div>
              <div>
                <Label className="text-xs">Quartier / Ville</Label>
                <Input value={location} onChange={(e) => setLocation(e.target.value)} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label className="text-xs">Limite quotidienne (GNF)</Label>
                  <Input type="number" value={dailyLimit} onChange={(e) => setDailyLimit(e.target.value)} />
                </div>
                <div>
                  <Label className="text-xs">Commission (0-1)</Label>
                  <Input type="number" step="0.001" value={commission} onChange={(e) => setCommission(e.target.value)} />
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button onClick={create} disabled={submitting || !phone || !business} className="gradient-primary w-full">
                {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créer l'agent"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {loading ? (
        <div className="py-8 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-primary" /></div>
      ) : agents.length === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-6">Aucun agent enregistré.</p>
      ) : (
        <div className="space-y-3">
          {agents.map((a) => (
            <AgentRowCard key={a.id} agent={a} fmt={fmt} onChanged={onChanged} />
          ))}
        </div>
      )}
    </section>
  );
}

function AgentRowCard({ agent, fmt, onChanged }: { agent: AgentRow; fmt: (n: number) => string; onChanged: () => void }) {
  const [open, setOpen] = useState(false);
  const [delta, setDelta] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  const adjust = async (sign: 1 | -1) => {
    const amount = Number(delta);
    if (!amount || amount <= 0) {
      toast({ title: "Montant invalide" });
      return;
    }
    setBusy(true);
    const { error } = await supabase.rpc("admin_adjust_agent_float", {
      p_agent_user_id: agent.user_id,
      p_delta_gnf: sign * amount,
      p_reason: reason || null,
    });
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    toast({ title: sign > 0 ? "Float crédité" : "Float débité" });
    setOpen(false);
    setDelta(""); setReason("");
    onChanged();
  };

  return (
    <div className="border border-border rounded-2xl p-4">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center shrink-0">
            <Store className="w-5 h-5 text-primary-foreground" />
          </div>
          <div className="min-w-0">
            <h3 className="font-semibold truncate">{agent.business_name}</h3>
            <p className="text-xs text-muted-foreground truncate">
              {agent.profile?.full_name ?? "—"} · {agent.profile?.phone ?? agent.user_id.slice(0, 8)}
            </p>
            {agent.location && <p className="text-xs text-muted-foreground truncate">{agent.location}</p>}
          </div>
        </div>
        <div className="text-right shrink-0">
          <p className="text-xs text-muted-foreground">Float</p>
          <p className="font-semibold">{fmt(agent.prepaid_float_gnf)}</p>
        </div>
      </div>
      <div className="flex items-center gap-2 mt-3">
        <span className="text-xs px-2 py-0.5 rounded-full bg-muted text-muted-foreground">{agent.status}</span>
        <span className="text-xs text-muted-foreground">Limite: {fmt(agent.daily_limit_gnf)}/j</span>
        <span className="text-xs text-muted-foreground">· {(agent.commission_rate * 100).toFixed(2)}%</span>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm" variant="outline" className="ml-auto">
              <Wallet className="w-4 h-4 mr-1" /> Float
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader><DialogTitle>Ajuster le float</DialogTitle></DialogHeader>
            <div className="space-y-3">
              <div>
                <Label className="text-xs">Montant (GNF)</Label>
                <Input type="number" min={0} value={delta} onChange={(e) => setDelta(e.target.value)} />
              </div>
              <div>
                <Label className="text-xs">Motif (optionnel)</Label>
                <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Cash reçu, etc." />
              </div>
              <p className="text-xs text-muted-foreground">
                Solde actuel: <strong>{fmt(agent.prepaid_float_gnf)}</strong>
              </p>
            </div>
            <DialogFooter className="grid grid-cols-2 gap-2">
              <Button variant="outline" disabled={busy} onClick={() => adjust(-1)}>Débiter</Button>
              <Button className="gradient-primary" disabled={busy} onClick={() => adjust(1)}>
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créditer"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  );
}

function FareRow({
  fare,
  Icon,
  saving,
  onSave,
}: {
  fare: Fare;
  Icon: React.ComponentType<{ className?: string }>;
  saving: boolean;
  onSave: (patch: Partial<Fare>) => void;
}) {
  const [base, setBase] = useState(String(fare.base_price));
  const [perKm, setPerKm] = useState(String(fare.price_per_km));

  return (
    <div className="border border-border rounded-2xl p-4">
      <div className="flex items-center gap-3 mb-3">
        <div className="w-9 h-9 rounded-xl gradient-primary flex items-center justify-center">
          <Icon className="w-5 h-5 text-primary-foreground" />
        </div>
        <div>
          <h3 className="font-semibold capitalize">{fare.ride_type}</h3>
          <p className="text-xs text-muted-foreground">Devise: {fare.currency}</p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <Label className="text-xs">Prix de base</Label>
          <Input type="number" min={0} value={base} onChange={(e) => setBase(e.target.value)} />
        </div>
        <div>
          <Label className="text-xs">Prix / km</Label>
          <Input type="number" min={0} value={perKm} onChange={(e) => setPerKm(e.target.value)} />
        </div>
      </div>
      <Button
        className="w-full mt-3 gradient-primary"
        disabled={saving}
        onClick={() => onSave({ base_price: Number(base), price_per_km: Number(perKm) })}
      >
        {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Enregistrer"}
      </Button>
    </div>
  );
}