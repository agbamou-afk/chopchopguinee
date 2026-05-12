import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { Loader2, LogOut, ShieldCheck, Bike, Car, KeyRound } from "lucide-react";

interface Fare {
  id: string;
  ride_type: string;
  base_price: number;
  price_per_km: number;
  currency: string;
  updated_at: string;
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
      }
      setLoading(false);
    })();
    return () => { sub.subscription.unsubscribe(); };
  }, [navigate]);

  const claimAdmin = async () => {
    if (!userId) return;
    setClaiming(true);
    // Allowed only when no admin exists yet — enforced via insert + check
    const { count } = await supabase
      .from("user_roles")
      .select("*", { count: "exact", head: true })
      .eq("role", "admin");
    if ((count ?? 0) > 0) {
      toast({ title: "Refusé", description: "Un administrateur existe déjà." });
      setClaiming(false);
      return;
    }
    const { error } = await supabase.from("user_roles").insert({ user_id: userId, role: "admin" });
    setClaiming(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
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
      </main>
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