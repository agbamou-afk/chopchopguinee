import { useState, useEffect } from "react";
import { useNavigate, Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { z } from "zod";
import { Loader2 } from "lucide-react";
import logo from "@/assets/logo.png";
import { Seo } from "@/components/Seo";

const passwordSchema = z.string().min(6, { message: "6 caractères minimum" }).max(72);
const emailSchema = z.string().trim().email({ message: "Email invalide" }).max(255);
// Guinea phone: accept digits, optional +, spaces. Normalize to E.164 with +224 default.
const phoneSchema = z
  .string()
  .trim()
  .regex(/^\+?[0-9\s]{8,15}$/, { message: "Téléphone invalide" });

function normalizePhone(raw: string): string {
  const digits = raw.replace(/\s+/g, "");
  if (digits.startsWith("+")) return digits;
  // Guinea local numbers (8-9 digits) → +224
  if (digits.length <= 9) return `+224${digits}`;
  return `+${digits}`;
}

export default function Auth() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [channel, setChannel] = useState<"phone" | "email">("phone");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [fullName, setFullName] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const routeByRole = async (uid: string) => {
    const { data: roles } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", uid);
    if (roles?.some((r) => r.role === "admin")) {
      navigate("/admin", { replace: true });
      return;
    }
    const { data: ap } = await supabase
      .from("agent_profiles")
      .select("user_id")
      .eq("user_id", uid)
      .maybeSingle();
    if (ap) {
      navigate("/agent", { replace: true });
      return;
    }
    navigate("/", { replace: true });
  };

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) routeByRole(data.session.user.id);
    });
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    // Validate password
    const pw = passwordSchema.safeParse(password);
    if (!pw.success) {
      toast({ title: "Erreur", description: pw.error.errors[0].message });
      return;
    }
    // Signup is phone-only (admins are created server-side)
    const useChannel = mode === "signup" ? "phone" : channel;

    if (useChannel === "phone") {
      const ph = phoneSchema.safeParse(phone);
      if (!ph.success) {
        toast({ title: "Erreur", description: ph.error.errors[0].message });
        return;
      }
    } else {
      const em = emailSchema.safeParse(email);
      if (!em.success) {
        toast({ title: "Erreur", description: em.error.errors[0].message });
        return;
      }
    }

    setLoading(true);
    try {
      if (mode === "signup") {
        const normalized = normalizePhone(phone);
        const { error } = await supabase.auth.signUp({
          phone: normalized,
          password,
          options: {
            data: { full_name: fullName.trim() || null },
          },
        });
        if (error) throw error;
        toast({
          title: "Compte créé",
          description: "Vous pouvez maintenant vous connecter avec votre numéro.",
        });
        setMode("signin");
      } else if (useChannel === "phone") {
        const normalized = normalizePhone(phone);
        const { data, error } = await supabase.auth.signInWithPassword({
          phone: normalized,
          password,
        });
        if (error) throw error;
        if (data.user) await routeByRole(data.user.id);
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        if (data.user) await routeByRole(data.user.id);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Erreur inconnue";
      toast({ title: "Échec", description: msg });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <Seo
        title="Connexion & inscription — CHOP CHOP"
        description="Connectez-vous ou créez votre compte CHOP CHOP par numéro de téléphone pour accéder aux courses, livraisons, marché et portefeuille en GNF."
        canonical="/auth"
      />
      <div className="w-full max-w-sm bg-card rounded-3xl shadow-elevated p-6">
        <div className="flex flex-col items-center mb-6">
          <img src={logo} alt="CHOP CHOP" className="h-20 w-auto object-contain mb-2" />
          <h1 className="text-xl font-bold text-foreground">Connexion CHOP CHOP</h1>
          <p className="text-sm text-muted-foreground">
            {mode === "signin"
              ? "Connectez-vous à votre compte"
              : "Créer un compte avec votre téléphone"}
          </p>
        </div>
        {mode === "signin" && (
          <div className="grid grid-cols-2 gap-1 p-1 bg-muted rounded-xl mb-4">
            <button
              type="button"
              onClick={() => setChannel("phone")}
              className={`py-2 text-sm font-medium rounded-lg transition-colors ${
                channel === "phone" ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"
              }`}
            >
              Téléphone
            </button>
            <button
              type="button"
              onClick={() => setChannel("email")}
              className={`py-2 text-sm font-medium rounded-lg transition-colors ${
                channel === "email" ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"
              }`}
            >
              Email (admin)
            </button>
          </div>
        )}
        <form onSubmit={submit} className="space-y-4">
          {mode === "signup" && (
            <div>
              <Label htmlFor="fullName">Nom complet</Label>
              <Input
                id="fullName"
                type="text"
                autoComplete="name"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Alpha Diallo"
              />
            </div>
          )}
          {mode === "signup" || channel === "phone" ? (
            <div>
              <Label htmlFor="phone">Téléphone</Label>
              <Input
                id="phone"
                type="tel"
                inputMode="tel"
                autoComplete="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+224 6XX XX XX XX"
                required
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Indicatif Guinée (+224) ajouté automatiquement.
              </p>
            </div>
          ) : (
            <div>
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
          )}
          <div>
            <Label htmlFor="password">Mot de passe</Label>
            <Input
              id="password"
              type="password"
              autoComplete={mode === "signup" ? "new-password" : "current-password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </div>
          <Button type="submit" disabled={loading} className="w-full h-12 gradient-primary">
            {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : mode === "signin" ? "Se connecter" : "Créer le compte"}
          </Button>
        </form>
        <button
          type="button"
          onClick={() => setMode(mode === "signin" ? "signup" : "signin")}
          className="w-full text-sm text-muted-foreground mt-4 hover:text-foreground"
        >
          {mode === "signin" ? "Pas de compte ? S'inscrire" : "Déjà un compte ? Se connecter"}
        </button>
        <Link to="/" className="block text-center text-xs text-muted-foreground mt-4 hover:underline">
          ← Retour à l'application
        </Link>
      </div>
    </div>
  );
}