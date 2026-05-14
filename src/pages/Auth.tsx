import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { z } from "zod";
import { Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { Seo } from "@/components/Seo";
import logo from "@/assets/logo.png";

const phoneSchema = z.string().trim().regex(/^\+?[0-9\s]{8,15}$/, "Téléphone invalide");
const emailSchema = z.string().trim().email("Email invalide").max(255);
const passwordSchema = z.string().min(6, "6 caractères minimum").max(72);
const nameSchema = z.string().trim().min(1, "Requis").max(60);

function normalizePhone(raw: string): string {
  const d = raw.replace(/\s+/g, "");
  if (d.startsWith("+")) return d;
  if (d.length <= 9) return `+224${d}`;
  return `+${d}`;
}

type Mode = "signin" | "signup";
type Channel = "phone_password" | "phone_otp" | "email_password";

export default function Auth() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const nextParam = params.get("next");
  const safeNext = nextParam && nextParam.startsWith("/") ? nextParam : null;
  const { ready, isLoggedIn, isAdmin, isProfileComplete } = useAuth();

  const [mode, setMode] = useState<Mode>("signin");
  const [channel, setChannel] = useState<Channel>("phone_password");
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [otpCode, setOtpCode] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [busy, setBusy] = useState(false);

  // After session is established, route by role + profile completeness.
  useEffect(() => {
    if (!ready || !isLoggedIn) return;
    if (!isProfileComplete) {
      navigate("/complete-profile", { replace: true });
      return;
    }
    if (safeNext) {
      navigate(safeNext, { replace: true });
      return;
    }
    navigate(isAdmin ? "/admin" : "/", { replace: true });
  }, [ready, isLoggedIn, isAdmin, isProfileComplete, safeNext, navigate]);

  const sendOtp = async () => {
    const v = phoneSchema.safeParse(phone);
    if (!v.success) {
      toast({ title: "Erreur", description: v.error.errors[0].message });
      return;
    }
    setBusy(true);
    const { error } = await supabase.auth.signInWithOtp({ phone: normalizePhone(phone) });
    setBusy(false);
    if (error) {
      toast({ title: "Échec envoi code", description: error.message });
      return;
    }
    setOtpSent(true);
    toast({ title: "Code envoyé", description: "Vérifiez vos SMS." });
  };

  const verifyOtp = async () => {
    if (!otpCode.trim()) return;
    setBusy(true);
    const { error } = await supabase.auth.verifyOtp({
      phone: normalizePhone(phone),
      token: otpCode.trim(),
      type: "sms",
    });
    setBusy(false);
    if (error) {
      toast({ title: "Code invalide", description: error.message });
      return;
    }
    // useEffect routes once session updates.
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (mode === "signup") {
      const fields = z
        .object({ first: nameSchema, last: nameSchema, phone: phoneSchema, password: passwordSchema })
        .safeParse({ first, last, phone, password });
      if (!fields.success) {
        toast({ title: "Erreur", description: fields.error.errors[0].message });
        return;
      }
      const emailOk = email ? emailSchema.safeParse(email) : { success: true };
      if (!emailOk.success) {
        toast({ title: "Erreur", description: "Email invalide" });
        return;
      }
      setBusy(true);
      const display = `${first.trim()} ${last.trim()}`;
      const { error } = await supabase.auth.signUp({
        phone: normalizePhone(phone),
        password,
        options: {
          data: {
            first_name: first.trim(),
            last_name: last.trim(),
            full_name: display,
            email: email.trim() || null,
          },
        },
      });
      setBusy(false);
      if (error) {
        toast({ title: "Échec inscription", description: error.message });
        return;
      }
      toast({
        title: "Compte créé",
        description: "Vous pouvez maintenant vous connecter.",
      });
      setMode("signin");
      setChannel("phone_password");
      return;
    }

    // signin
    if (channel === "phone_otp") {
      if (!otpSent) await sendOtp();
      else await verifyOtp();
      return;
    }
    if (channel === "email_password") {
      const e1 = emailSchema.safeParse(email);
      const p1 = passwordSchema.safeParse(password);
      if (!e1.success || !p1.success) {
        toast({ title: "Erreur", description: "Email ou mot de passe invalide" });
        return;
      }
      setBusy(true);
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      setBusy(false);
      if (error) toast({ title: "Échec", description: error.message });
      return;
    }
    // phone_password
    const ph = phoneSchema.safeParse(phone);
    const pw = passwordSchema.safeParse(password);
    if (!ph.success || !pw.success) {
      toast({ title: "Erreur", description: "Téléphone ou mot de passe invalide" });
      return;
    }
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({
      phone: normalizePhone(phone),
      password,
    });
    setBusy(false);
    if (error) toast({ title: "Échec", description: error.message });
  };

  const channelTabs: { key: Channel; label: string }[] = [
    { key: "phone_password", label: "Mot de passe" },
    { key: "phone_otp", label: "Code SMS" },
    { key: "email_password", label: "Email" },
  ];

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <Seo
        title="Connexion & inscription — CHOP CHOP"
        description="Connectez-vous ou créez votre compte CHOP CHOP par téléphone pour accéder aux courses, livraisons, marché et portefeuille en GNF."
        canonical="/auth"
      />
      <div className="w-full max-w-sm bg-card rounded-3xl shadow-elevated p-6">
        <div className="flex flex-col items-center mb-6">
          <img
            src={logo}
            alt="CHOP CHOP"
            className="h-20 w-auto object-contain mb-2 mix-blend-multiply dark:mix-blend-screen"
          />
          <h1 className="text-xl font-bold text-foreground">CHOP CHOP</h1>
          <p className="text-sm text-muted-foreground">
            {mode === "signin" ? "Connectez-vous" : "Créer votre compte"}
          </p>
        </div>

        {mode === "signin" && (
          <div className="grid grid-cols-3 gap-1 p-1 bg-muted rounded-xl mb-4">
            {channelTabs.map((t) => (
              <button
                key={t.key}
                type="button"
                onClick={() => {
                  setChannel(t.key);
                  setOtpSent(false);
                  setOtpCode("");
                }}
                className={`py-2 text-xs font-medium rounded-lg transition-colors ${
                  channel === t.key ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>
        )}

        <form onSubmit={submit} className="space-y-3">
          {mode === "signup" && (
            <>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <Label htmlFor="first">Prénom</Label>
                  <Input id="first" value={first} onChange={(e) => setFirst(e.target.value)} required />
                </div>
                <div>
                  <Label htmlFor="last">Nom</Label>
                  <Input id="last" value={last} onChange={(e) => setLast(e.target.value)} required />
                </div>
              </div>
              <div>
                <Label htmlFor="email-signup">Email (optionnel)</Label>
                <Input
                  id="email-signup"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </div>
            </>
          )}

          {(mode === "signup" || channel === "phone_password" || channel === "phone_otp") && (
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
          )}

          {mode === "signin" && channel === "email_password" && (
            <div>
              <Label htmlFor="email-signin">Email</Label>
              <Input
                id="email-signin"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
          )}

          {(mode === "signup" || channel !== "phone_otp") && (
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
          )}

          {mode === "signin" && channel === "phone_otp" && otpSent && (
            <div>
              <Label htmlFor="otp">Code reçu par SMS</Label>
              <Input
                id="otp"
                inputMode="numeric"
                autoComplete="one-time-code"
                value={otpCode}
                onChange={(e) => setOtpCode(e.target.value)}
                maxLength={8}
                required
              />
              <button
                type="button"
                onClick={() => {
                  setOtpSent(false);
                  setOtpCode("");
                }}
                className="text-xs text-muted-foreground mt-1 underline"
              >
                Renvoyer le code
              </button>
            </div>
          )}

          <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
            {busy ? (
              <Loader2 className="w-5 h-5 animate-spin" />
            ) : mode === "signup" ? (
              "Créer le compte"
            ) : channel === "phone_otp" && !otpSent ? (
              "Envoyer le code"
            ) : channel === "phone_otp" ? (
              "Vérifier le code"
            ) : (
              "Se connecter"
            )}
          </Button>
        </form>

        <button
          type="button"
          onClick={() => {
            setMode(mode === "signin" ? "signup" : "signin");
            setOtpSent(false);
            setOtpCode("");
          }}
          className="w-full text-sm text-muted-foreground mt-4 hover:text-foreground"
        >
          {mode === "signin" ? "Pas de compte ? S'inscrire" : "Déjà un compte ? Se connecter"}
        </button>
        <Link to="/" className="block text-center text-xs text-muted-foreground mt-4 hover:underline">
          ← Retour à l'application
        </Link>

        <div className="mt-6 pt-4 border-t border-border">
          <p className="text-[11px] uppercase tracking-wider text-muted-foreground text-center mb-2">
            Comptes de démonstration
          </p>
          <div className="grid grid-cols-2 gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                // Clean any prior session/state so the next demo account starts fresh.
                try { await supabase.auth.signOut({ scope: "local" }); } catch { /* noop */ }
                try {
                  sessionStorage.removeItem("cc_driver_mode");
                  localStorage.removeItem("cc_realtime_trip");
                } catch { /* noop */ }
                const { error } = await supabase.auth.signInWithPassword({
                  email: "demo.client@chopchop.gn",
                  password: "demo1234",
                });
                setBusy(false);
                if (error) toast({ title: "Échec démo client", description: error.message });
              }}
            >
              Demo Client
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                try { await supabase.auth.signOut({ scope: "local" }); } catch { /* noop */ }
                try {
                  sessionStorage.removeItem("cc_driver_mode");
                  localStorage.removeItem("cc_realtime_trip");
                } catch { /* noop */ }
                const { error } = await supabase.auth.signInWithPassword({
                  email: "demo.driver@chopchop.gn",
                  password: "demo1234",
                });
                setBusy(false);
                if (error) toast({ title: "Échec démo chauffeur", description: error.message });
              }}
            >
              Demo Chauffeur
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}