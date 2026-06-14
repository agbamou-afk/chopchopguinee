import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { z } from "zod";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { GuineaPhoneInput } from "@/components/ui/guinea-phone-input";
import {
  GUINEA_PHONE_INVALID_MESSAGE,
  extractGuineaLocal,
  isValidGuineaLocal,
  normalizeGuineaPhone,
} from "@/lib/phone/guinea";
import { persistMerchantAppMode, resolveMerchantPostAuthRoute } from "@/lib/merchantRouting";

const schema = z.object({
  first_name: z.string().trim().min(1, "Prénom requis").max(60),
  last_name: z.string().trim().min(1, "Nom requis").max(60),
  email: z.string().trim().email("Email invalide").max(255).optional().or(z.literal("")),
});

export default function CompleteProfile() {
  const { ready, isLoggedIn, isProfileComplete, user, profile, refresh, signupIntent, requestedDriverVehicle } = useAuth();
  const navigate = useNavigate();
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!ready) return;
    if (!isLoggedIn) navigate("/auth", { replace: true });
    if (isLoggedIn && isProfileComplete) {
      navigate("/", { replace: true });
      return;
    }
    if (profile) {
      setFirst(profile.first_name ?? "");
      setLast(profile.last_name ?? "");
      setPhone(extractGuineaLocal(profile.phone ?? user?.phone ?? ""));
      setEmail(profile.email ?? user?.email ?? "");
    }
  }, [ready, isLoggedIn, isProfileComplete, profile, user, navigate]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = schema.safeParse({ first_name: first, last_name: last, email });
    if (!parsed.success) {
      toast({ title: "Erreur", description: parsed.error.errors[0].message });
      return;
    }
    if (!isValidGuineaLocal(phone)) {
      toast({ title: "Erreur", description: GUINEA_PHONE_INVALID_MESSAGE });
      return;
    }
    if (!user) return;
    setBusy(true);
    const display = `${parsed.data.first_name} ${parsed.data.last_name}`.trim();
    const { error } = await supabase
      .from("profiles")
      .upsert(
        {
          user_id: user.id,
          first_name: parsed.data.first_name,
          last_name: parsed.data.last_name,
          full_name: display,
          display_name: display,
          phone: normalizeGuineaPhone(phone),
          email: parsed.data.email || null,
          last_profile_confirmed_at: new Date().toISOString(),
        },
        { onConflict: "user_id" },
      );
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    await refresh();
    // Make sure the signed-in user has a client wallet (idempotent).
    try {
      await supabase.rpc("wallet_ensure", { _party_type: "client" });
    } catch {
      /* non-blocking */
    }
    toast({ title: "Profil complété" });
    // Driver applicants must land directly in the driver application flow,
    // never the client home, even if they completed profile after email
    // confirmation.
    if (signupIntent === "driver") {
      try { sessionStorage.setItem("cc_driver_mode_choice", "driver"); } catch { /* noop */ }
      const v = requestedDriverVehicle ?? "moto";
      navigate(`/driver/apply?intent=${encodeURIComponent(v)}`, { replace: true });
    } else if (signupIntent === "merchant") {
      try { await persistMerchantAppMode(user.id); } catch { /* noop */ }
      const route = await resolveMerchantPostAuthRoute(user.id, { preferSlides: true });
      navigate(route, { replace: true });
    } else {
      navigate("/", { replace: true });
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm bg-card rounded-3xl shadow-elevated p-6">
        <div className="flex flex-col items-center mb-6">
          <BrandLogo size="lg" loading="lazy" className="mb-2" />
          <h1 className="text-xl font-bold">Complétez votre profil</h1>
          <p className="text-sm text-muted-foreground text-center">
            Quelques informations pour finaliser votre compte CHOPCHOP.
          </p>
        </div>
        <form onSubmit={submit} className="space-y-3">
          <div>
            <Label htmlFor="first_name">Prénom</Label>
            <Input id="first_name" value={first} onChange={(e) => setFirst(e.target.value)} required />
          </div>
          <div>
            <Label htmlFor="last_name">Nom</Label>
            <Input id="last_name" value={last} onChange={(e) => setLast(e.target.value)} required />
          </div>
          <div>
            <Label htmlFor="phone">Téléphone</Label>
            <GuineaPhoneInput id="phone" value={phone} onChange={setPhone} required />
          </div>
          <div>
            <Label htmlFor="email">Email (optionnel)</Label>
            <Input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
          <Button type="submit" disabled={busy} className="w-full h-12 gradient-primary">
            {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Enregistrer"}
          </Button>
        </form>
      </div>
    </div>
  );
}