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
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Checkbox } from "@/components/ui/checkbox";
import { TERMS_VERSION, PRIVACY_VERSION, recordLegalAcceptance } from "@/lib/legal";
import { Bike, Car, Package, ShoppingBag } from "lucide-react";
import { cn } from "@/lib/utils";
import { GuineaPhoneInput } from "@/components/ui/guinea-phone-input";
import {
  GUINEA_PHONE_INVALID_MESSAGE,
  isValidGuineaLocal,
  normalizeGuineaPhone,
} from "@/lib/phone/guinea";
import { EmailConfirmationPendingCard } from "@/components/auth/EmailConfirmationPendingCard";

type SignupIntent = "client" | "driver";
type DriverVehicleIntent = "moto" | "toktok" | "livraison";
const DRIVER_INTENT_STORAGE_KEY = "cc_signup_driver_intent";

const emailSchema = z
  .string()
  .trim()
  .email("Adresse email invalide. Vérifiez l'adresse et réessayez.")
  .max(255);
const passwordSchema = z
  .string()
  .min(6, "Mot de passe trop faible. Utilisez au moins 6 caractères.")
  .max(72);
const nameSchema = z.string().trim().min(1, "Requis").max(60);

// Pilot launch: email + password only. Phone OTP / phone password are disabled
// until an SMS provider (Twilio / Messaging Service SID) is configured in
// Lovable Cloud → Users → Auth → Phone.
type Mode = "signin" | "signup";

function frenchAuthError(raw: string | undefined): string {
  const msg = (raw ?? "").toLowerCase();
  if (!msg) return "Création du compte impossible pour le moment. Contactez le support CHOPCHOP.";
  if (msg.includes("already") || msg.includes("registered") || msg.includes("exists"))
    return "Un compte existe déjà avec cette adresse email.";
  if (msg.includes("invalid login") || msg.includes("invalid credentials"))
    return "Email ou mot de passe incorrect.";
  if (msg.includes("email") && msg.includes("invalid"))
    return "Adresse email invalide. Vérifiez l'adresse et réessayez.";
  if (msg.includes("password"))
    return "Mot de passe trop faible. Utilisez au moins 6 caractères.";
  if (msg.includes("network") || msg.includes("fetch") || msg.includes("timeout"))
    return "Connexion instable. Réessayez dans quelques instants.";
  if (msg.includes("rate") || msg.includes("too many"))
    return "Trop de tentatives. Patientez quelques instants.";
  if (msg.includes("not confirmed") || msg.includes("confirm"))
    return "Compte non confirmé. Vérifiez votre email pour activer votre compte.";
  // Never surface Twilio / SMS internals to the user.
  if (msg.includes("twilio") || msg.includes("sms") || msg.includes("provider"))
    return "Connexion par téléphone bientôt disponible. Utilisez votre email pour le moment.";
  return "Création du compte impossible pour le moment. Contactez le support CHOPCHOP.";
}

export default function Auth() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const nextParam = params.get("next");
  const safeNext = nextParam && nextParam.startsWith("/") ? nextParam : null;
  const { ready, isLoggedIn, isAdmin, isProfileComplete, signupIntent, requestedDriverVehicle } = useAuth();

  const [mode, setMode] = useState<Mode>("signin");
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [acceptLegal, setAcceptLegal] = useState(false);
  const [intent, setIntent] = useState<SignupIntent>("client");
  const [vehicle, setVehicle] = useState<DriverVehicleIntent>("moto");
  const [pendingConfirm, setPendingConfirm] = useState<
    { email: string; intent: SignupIntent } | null
  >(null);

  // After session is established, route by role + profile completeness.
  useEffect(() => {
    if (!ready || !isLoggedIn) return;
    if (!isProfileComplete) {
      navigate("/complete-profile", { replace: true });
      return;
    }
    // Honor a stored driver-applicant intent from signup. We route to the
    // driver application flow and flip the global mode to driver so the
    // user lands on the driver dashboard pending-review state after.
    try {
      const raw =
        typeof window !== "undefined"
          ? sessionStorage.getItem(DRIVER_INTENT_STORAGE_KEY)
          : null;
      const parsedVehicle = (() => {
        if (!raw) return null;
        try {
          const p = JSON.parse(raw) as { vehicle?: DriverVehicleIntent };
          return p?.vehicle ?? null;
        } catch { return null; }
      })();
      // Source of truth in priority order:
      //   1) sessionStorage (same-device signup → confirm)
      //   2) user_metadata.signup_intent (cross-device email confirm,
      //      browser refresh, or re-login)
      const wantsDriver = !!parsedVehicle || signupIntent === "driver";
      if (wantsDriver) {
        sessionStorage.removeItem(DRIVER_INTENT_STORAGE_KEY);
        sessionStorage.setItem("cc_driver_mode_choice", "driver");
        const v = parsedVehicle ?? requestedDriverVehicle ?? "moto";
        navigate(`/driver/apply?intent=${encodeURIComponent(v)}`, { replace: true });
        return;
      }
    } catch {
      /* noop */
    }
    if (safeNext) {
      navigate(safeNext, { replace: true });
      return;
    }
    navigate(isAdmin ? "/admin" : "/", { replace: true });
  }, [ready, isLoggedIn, isAdmin, isProfileComplete, signupIntent, requestedDriverVehicle, safeNext, navigate]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (mode === "signup") {
      if (!acceptLegal) {
        toast({
          title: "Acceptation requise",
          description: "Vous devez accepter les Conditions d'utilisation et la Politique de confidentialité.",
        });
        return;
      }
      // Hard block: refuse if "email" field looks like a phone number.
      if (/^\+?[0-9\s]{8,15}$/.test(email.trim()) && !email.includes("@")) {
        toast({
          title: "Email requis",
          description:
            "Utilisez votre adresse email pour créer un compte. La connexion par téléphone arrive bientôt.",
        });
        return;
      }
      const fields = z
        .object({
          first: nameSchema,
          last: nameSchema,
          email: emailSchema,
          password: passwordSchema,
        })
        .safeParse({ first, last, email, password });
      if (!fields.success) {
        toast({ title: "Erreur", description: fields.error.errors[0].message });
        return;
      }
      if (!isValidGuineaLocal(phone)) {
        toast({ title: "Erreur", description: GUINEA_PHONE_INVALID_MESSAGE });
        return;
      }
      setBusy(true);
      const display = `${first.trim()} ${last.trim()}`;
      // Ban preflight: refuse signup if the email or phone is on the
      // active ban list. Public copy avoids enumeration leakage.
      try {
        const { data: allowedRes } = await supabase.rpc("check_signup_allowed", {
          _email: email.trim(),
          _phone: normalizeGuineaPhone(phone),
        });
        const allowed = (allowedRes as { allowed?: boolean } | null)?.allowed !== false;
        if (!allowed) {
          setBusy(false);
          toast({
            title: "Inscription impossible",
            description:
              "Cette inscription ne peut pas être finalisée. Contactez le support CHOPCHOP.",
          });
          return;
        }
      } catch {
        /* preflight is best-effort; backend ban checks remain authoritative */
      }
      const { data: signUpData, error } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: {
          emailRedirectTo: `${window.location.origin}/`,
          data: {
            first_name: first.trim(),
            last_name: last.trim(),
            full_name: display,
            phone: normalizeGuineaPhone(phone),
            terms_version_accepted: TERMS_VERSION,
            privacy_version_accepted: PRIVACY_VERSION,
            signup_intent: intent,
            requested_driver_vehicle: intent === "driver" ? vehicle : null,
          },
        },
      });
      setBusy(false);
      if (error) {
        toast({ title: "Échec inscription", description: frenchAuthError(error.message) });
        return;
      }
      // Supabase anti-enumeration: when the email is already registered,
      // signUp returns 200 with a user object whose `identities` array is
      // empty AND no new confirmation email is sent. Detect this and route
      // the user to a clear path (sign in or resend confirmation) instead
      // of leaving them on a pending screen forever.
      const identities = signUpData?.user?.identities;
      const alreadyRegistered =
        !signUpData?.session && Array.isArray(identities) && identities.length === 0;
      if (alreadyRegistered) {
        toast({
          title: "Adresse déjà utilisée",
          description:
            "Cette adresse est peut-être déjà associée à un compte. Si vous n'avez pas confirmé votre compte, renvoyez l'email de confirmation.",
        });
        setMode("signin");
        setPassword("");
        setPendingConfirm({ email: email.trim(), intent });
        return;
      }
      // Persist intent so post-confirmation routing can branch to the
      // driver application flow. Selecting "driver" never grants any
      // capability on its own — the application stays pending until an
      // admin approves it.
      try {
        if (intent === "driver" && typeof window !== "undefined") {
          sessionStorage.setItem(
            DRIVER_INTENT_STORAGE_KEY,
            JSON.stringify({ vehicle }),
          );
        }
      } catch {
        /* noop */
      }
      // Record acceptance immediately if a session was created (auto-confirm).
      void recordLegalAcceptance({ source: "signup" });
      // Pilot mode: email confirmation is NOT required. If a session was
      // created (auto-confirm), the AuthContext effect above will route to
      // /complete-profile then to client home or /driver/apply based on intent.
      toast({
        title: "Compte créé avec succès",
        description:
          intent === "driver"
            ? "Compte créé. Finalisez votre demande chauffeur/coursier."
            : "Bienvenue sur CHOPCHOP.",
      });
      return;
    }

    // signin — email + password only
    // If user typed a phone number into the email field, redirect them.
    if (/^\+?[0-9\s]{8,15}$/.test(email.trim()) && !email.includes("@")) {
      toast({
        title: "Email requis",
        description:
          "Utilisez votre adresse email pour vous connecter. La connexion par téléphone arrive bientôt.",
      });
      return;
    }
    const e1 = emailSchema.safeParse(email);
    const p1 = passwordSchema.safeParse(password);
    if (!e1.success || !p1.success) {
      toast({ title: "Erreur", description: "Email ou mot de passe invalide." });
      return;
    }
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    setBusy(false);
    if (error) {
      const msg = (error.message ?? "").toLowerCase();
      if (msg.includes("not confirmed") || msg.includes("confirm")) {
        // Pilot mode: confirmation is disabled for new signups. Older
        // unconfirmed accounts may still hit this. Surface a clear toast
        // and offer a one-tap resend rather than trapping the user.
        toast({
          title: "Compte en cours d'activation",
          description:
            "Votre compte est en cours d'activation. Réessayez dans un instant ou contactez le support CHOPCHOP.",
        });
        return;
      }
      toast({ title: "Échec", description: frenchAuthError(error.message) });
    }
  };

  const resendConfirmation = async () => {
    const e1 = emailSchema.safeParse(email);
    if (!e1.success) {
      toast({ title: "Email requis", description: "Entrez votre adresse email puis réessayez." });
      return;
    }
    setBusy(true);
    const { error } = await supabase.auth.resend({
      type: "signup",
      email: email.trim(),
      options: { emailRedirectTo: `${window.location.origin}/` },
    });
    setBusy(false);
    if (error) {
      toast({ title: "Échec", description: frenchAuthError(error.message) });
      return;
    }
    toast({
      title: "Email de confirmation renvoyé",
      description: "Vérifiez votre boîte de réception et vos spams.",
    });
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <Seo
        title="Connexion & inscription — CHOPCHOP"
        description="Connectez-vous ou créez votre compte CHOPCHOP par email pour accéder aux courses, livraisons, marché et portefeuille en GNF."
        canonical="/auth"
      />
      {pendingConfirm ? (
        <EmailConfirmationPendingCard
          email={pendingConfirm.email}
          intent={pendingConfirm.intent}
          onAlreadyConfirmed={() => {
            setMode("signin");
            setEmail(pendingConfirm.email);
            setPassword("");
            setPendingConfirm(null);
            toast({
              title: "Connexion",
              description: "Connectez-vous avec votre email et mot de passe.",
            });
          }}
          onUseAnotherEmail={() => {
            setMode("signup");
            setEmail("");
            setPassword("");
            setPendingConfirm(null);
          }}
        />
      ) : (
      <div className="w-full max-w-sm bg-card rounded-3xl shadow-elevated p-6">
        <div className="flex flex-col items-center mb-6">
          <BrandLogo size="lg" className="mb-2" />
          <p className="text-sm text-muted-foreground">
            {mode === "signin" ? "Connectez-vous" : "Créer votre compte"}
          </p>
        </div>

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
                <Label htmlFor="email-signup">Email</Label>
                <Input
                  id="email-signup"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
              <div>
                <Label htmlFor="phone">Téléphone</Label>
                <GuineaPhoneInput
                  id="phone"
                  value={phone}
                  onChange={setPhone}
                  required
                />
                <p className="text-[11px] text-muted-foreground mt-1">
                  Tapez uniquement votre numéro local. L'indicatif +224 est déjà inclus.
                </p>
              </div>

              <div className="pt-1">
                <Label className="text-xs uppercase tracking-wide text-muted-foreground">
                  Comment souhaitez-vous utiliser CHOPCHOP ?
                </Label>
                <div className="mt-2 grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setIntent("client")}
                    className={cn(
                      "flex flex-col items-start gap-1 p-3 rounded-2xl border text-left transition-colors",
                      intent === "client"
                        ? "border-primary bg-primary/5"
                        : "border-border bg-card",
                    )}
                  >
                    <ShoppingBag className="w-5 h-5 text-primary" />
                    <span className="text-sm font-semibold text-foreground">Client</span>
                    <span className="text-[11px] text-muted-foreground leading-snug">
                      Commander, acheter, envoyer ou vous déplacer.
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => setIntent("driver")}
                    className={cn(
                      "flex flex-col items-start gap-1 p-3 rounded-2xl border text-left transition-colors",
                      intent === "driver"
                        ? "border-primary bg-primary/5"
                        : "border-border bg-card",
                    )}
                  >
                    <Bike className="w-5 h-5 text-primary" />
                    <span className="text-sm font-semibold text-foreground">
                      Chauffeur / Coursier
                    </span>
                    <span className="text-[11px] text-muted-foreground leading-snug">
                      Recevoir des courses et livraisons après vérification.
                    </span>
                  </button>
                </div>

                {intent === "driver" && (
                  <div className="mt-2 space-y-2">
                    <p className="text-[11px] text-muted-foreground">
                      Quel service souhaitez-vous offrir ?
                    </p>
                    <div className="grid grid-cols-3 gap-2">
                      {([
                        { id: "moto" as const, label: "Moto", icon: Bike },
                        { id: "toktok" as const, label: "TokTok", icon: Car },
                        { id: "livraison" as const, label: "Livraison", icon: Package },
                      ]).map((opt) => (
                        <button
                          key={opt.id}
                          type="button"
                          onClick={() => setVehicle(opt.id)}
                          className={cn(
                            "flex flex-col items-center gap-1 p-2 rounded-xl border text-xs",
                            vehicle === opt.id
                              ? "border-primary bg-primary/5 text-foreground"
                              : "border-border bg-card text-muted-foreground",
                          )}
                        >
                          <opt.icon className="w-4 h-4" />
                          {opt.label}
                        </button>
                      ))}
                    </div>
                    <p className="text-[11px] text-muted-foreground">
                      Votre compte sera créé en attente de vérification. Vous ne
                      pourrez recevoir de missions qu'après l'approbation de
                      l'équipe CHOPCHOP.
                    </p>
                  </div>
                )}
              </div>
            </>
          )}

          {mode === "signin" && (
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

          <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
            {busy ? (
              <Loader2 className="w-5 h-5 animate-spin" />
            ) : mode === "signup" ? (
              "Créer le compte"
            ) : (
              "Se connecter"
            )}
          </Button>

          {mode === "signup" && (
            <label className="flex items-start gap-2 text-[12px] text-muted-foreground pt-1">
              <Checkbox
                checked={acceptLegal}
                onCheckedChange={(v) => setAcceptLegal(v === true)}
                className="mt-0.5"
              />
              <span>
                J'accepte les{" "}
                <Link to="/terms" target="_blank" className="text-primary underline">
                  Conditions d'utilisation
                </Link>{" "}
                et la{" "}
                <Link to="/privacy" target="_blank" className="text-primary underline">
                  Politique de confidentialité
                </Link>{" "}
                de CHOPCHOP.
              </span>
            </label>
          )}

          {mode === "signin" && (
            <p className="text-[11px] text-muted-foreground text-center pt-1">
              Connexion par téléphone bientôt disponible.
            </p>
          )}

          {mode === "signin" && (
            <button
              type="button"
              onClick={resendConfirmation}
              disabled={busy}
              className="block w-full text-[12px] text-primary underline text-center pt-1"
            >
              Renvoyer l'email de confirmation
            </button>
          )}
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
      )}
    </div>
  );
}