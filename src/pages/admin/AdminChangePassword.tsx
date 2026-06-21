import { useEffect, useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { Loader2, ShieldAlert, KeyRound, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card } from "@/components/ui/card";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

const TEMP_PASSWORD = "Welcome%2026";
const MIN_LENGTH = 10;

function weakPassword(pw: string): string | null {
  if (pw.length < MIN_LENGTH) return `Au moins ${MIN_LENGTH} caractères.`;
  if (pw === TEMP_PASSWORD) return "Vous ne pouvez pas réutiliser le mot de passe temporaire.";
  if (!/[A-Z]/.test(pw)) return "Ajoutez au moins une majuscule.";
  if (!/[a-z]/.test(pw)) return "Ajoutez au moins une minuscule.";
  if (!/[0-9]/.test(pw)) return "Ajoutez au moins un chiffre.";
  if (/^(.)\1+$/.test(pw)) return "Mot de passe trop simple.";
  if (/^(password|welcome|admin|chopchop|123456)/i.test(pw)) return "Mot de passe trop évident.";
  return null;
}

export default function AdminChangePassword() {
  const navigate = useNavigate();
  const { ready, isLoggedIn, user, signOut } = useAuth();
  const [checking, setChecking] = useState(true);
  const [mustChange, setMustChange] = useState<boolean | null>(null);
  const [pw1, setPw1] = useState("");
  const [pw2, setPw2] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      if (!user?.id) { setChecking(false); return; }
      const { data } = await supabase
        .from("admin_users")
        .select("must_change_password,status")
        .eq("user_id", user.id)
        .maybeSingle();
      if (!active) return;
      setMustChange(Boolean(data?.must_change_password) && data?.status === "active");
      setChecking(false);
    })();
    return () => { active = false; };
  }, [user?.id]);

  if (!ready || checking) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }
  if (!isLoggedIn) return <Navigate to="/auth?next=%2Fadmin%2Fchange-password" replace />;
  // Only staff with the flag may render this page.
  if (mustChange === false) return <Navigate to="/admin" replace />;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const err = weakPassword(pw1);
    if (err) { toast({ title: "Mot de passe refusé", description: err }); return; }
    if (pw1 !== pw2) { toast({ title: "Les mots de passe ne correspondent pas" }); return; }
    setBusy(true);
    const { error } = await supabase.auth.updateUser({ password: pw1 });
    if (error) {
      setBusy(false);
      toast({ title: "Échec", description: error.message });
      return;
    }
    const { error: rpcErr } = await supabase.rpc("admin_clear_must_change_password");
    setBusy(false);
    if (rpcErr) {
      toast({ title: "Mot de passe modifié, mais flag non effacé", description: rpcErr.message });
      return;
    }
    toast({ title: "Mot de passe mis à jour" });
    navigate("/admin", { replace: true });
  };

  const doSignOut = async () => {
    await signOut();
    navigate("/auth", { replace: true });
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md p-6 space-y-5">
        <div className="flex items-start gap-3">
          <div className="rounded-lg bg-amber-500/15 text-amber-600 dark:text-amber-400 p-2">
            <ShieldAlert className="w-5 h-5" />
          </div>
          <div>
            <h1 className="text-lg font-semibold">Changer votre mot de passe</h1>
            <p className="text-sm text-muted-foreground mt-1">
              Votre compte a été créé avec un mot de passe temporaire. Vous devez le
              changer avant d'accéder à l'administration CHOPCHOP.
            </p>
          </div>
        </div>

        <form className="space-y-3" onSubmit={onSubmit}>
          <div>
            <Label className="text-xs">Nouveau mot de passe</Label>
            <Input
              type="password"
              autoComplete="new-password"
              value={pw1}
              onChange={(e) => setPw1(e.target.value)}
              placeholder={`Au moins ${MIN_LENGTH} caractères`}
              required
            />
          </div>
          <div>
            <Label className="text-xs">Confirmer le nouveau mot de passe</Label>
            <Input
              type="password"
              autoComplete="new-password"
              value={pw2}
              onChange={(e) => setPw2(e.target.value)}
              required
            />
          </div>
          <p className="text-[11px] text-muted-foreground">
            Minimum 10 caractères avec majuscule, minuscule et chiffre. Le mot de passe
            temporaire <span className="font-mono">{TEMP_PASSWORD}</span> est interdit.
          </p>
          <Button type="submit" disabled={busy} className="w-full gradient-primary">
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : (
              <><KeyRound className="w-4 h-4 mr-1" /> Mettre à jour</>
            )}
          </Button>
        </form>

        <div className="pt-2 border-t border-border/60">
          <Button variant="ghost" size="sm" className="w-full" onClick={doSignOut}>
            <LogOut className="w-4 h-4 mr-1" /> Se déconnecter
          </Button>
        </div>
      </Card>
    </div>
  );
}