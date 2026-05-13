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
import logo from "@/assets/logo.png";

const schema = z.object({
  first_name: z.string().trim().min(1, "Prénom requis").max(60),
  last_name: z.string().trim().min(1, "Nom requis").max(60),
  phone: z.string().trim().regex(/^\+?[0-9\s]{8,15}$/, "Téléphone invalide"),
  email: z.string().trim().email("Email invalide").max(255).optional().or(z.literal("")),
});

function normalizePhone(raw: string): string {
  const d = raw.replace(/\s+/g, "");
  if (d.startsWith("+")) return d;
  if (d.length <= 9) return `+224${d}`;
  return `+${d}`;
}

export default function CompleteProfile() {
  const { ready, isLoggedIn, user, profile, refresh } = useAuth();
  const navigate = useNavigate();
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!ready) return;
    if (!isLoggedIn) navigate("/auth", { replace: true });
    if (profile) {
      setFirst(profile.first_name ?? "");
      setLast(profile.last_name ?? "");
      setPhone(profile.phone ?? user?.phone ?? "");
      setEmail(profile.email ?? user?.email ?? "");
    }
  }, [ready, isLoggedIn, profile, user, navigate]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = schema.safeParse({ first_name: first, last_name: last, phone, email });
    if (!parsed.success) {
      toast({ title: "Erreur", description: parsed.error.errors[0].message });
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
          phone: normalizePhone(parsed.data.phone),
          email: parsed.data.email || null,
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
    navigate("/", { replace: true });
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm bg-card rounded-3xl shadow-elevated p-6">
        <div className="flex flex-col items-center mb-6">
          <img src={logo} alt="CHOP CHOP" className="h-16 w-auto object-contain mb-2 mix-blend-multiply" />
          <h1 className="text-xl font-bold">Complétez votre profil</h1>
          <p className="text-sm text-muted-foreground text-center">
            Quelques informations pour finaliser votre compte CHOP CHOP.
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
            <Input id="phone" type="tel" inputMode="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+224 6XX XX XX XX" required />
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