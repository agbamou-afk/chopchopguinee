import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Seo } from "@/components/Seo";

/**
 * Periodic profile reconfirmation (every 60 days). Distinct from required
 * profile completion: this page only shows for users whose profile is already
 * complete, and is gated on `needsProfileReconfirmation`. "Confirm" only
 * touches the timestamp; "Modify" sends the user to the full edit page.
 */
export default function ConfirmProfile() {
  const { ready, isLoggedIn, profile, refresh, needsProfileReconfirmation } = useAuth();
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);

  if (!ready) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }
  if (!isLoggedIn) { navigate("/auth?mode=signin", { replace: true }); return null; }
  // If reconfirmation isn't due anymore (e.g. user landed here manually), just
  // send them home — never trap them.
  if (!needsProfileReconfirmation) { navigate("/", { replace: true }); return null; }

  const confirm = async () => {
    if (!profile) return;
    setBusy(true);
    const { error } = await supabase
      .from("profiles")
      .update({ last_profile_confirmed_at: new Date().toISOString() })
      .eq("user_id", profile.user_id);
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message, variant: "destructive" });
      return;
    }
    await refresh();
    toast({ title: "Informations confirmées" });
    navigate("/", { replace: true });
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <Seo title="Confirmez vos informations" description="Vérification périodique du profil CHOP CHOP" />
      <Card className="w-full max-w-sm p-6 space-y-4">
        <div className="flex flex-col items-center">
          <BrandLogo size="lg" loading="lazy" className="mb-2" />
          <h1 className="text-xl font-bold text-center">Confirmez vos informations</h1>
          <p className="text-sm text-muted-foreground text-center mt-1">
            Pour garder votre compte à jour, vérifiez vos informations tous les 60 jours.
          </p>
        </div>
        <div className="rounded-xl border border-border/60 divide-y divide-border/60 text-sm">
          <Row label="Nom" value={`${profile?.first_name ?? ""} ${profile?.last_name ?? ""}`.trim() || profile?.full_name || "—"} />
          <Row label="Téléphone" value={profile?.phone ?? "—"} />
          <Row label="Email" value={profile?.email ?? "—"} />
        </div>
        <Button onClick={confirm} disabled={busy} className="w-full h-12 gradient-primary">
          {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Confirmer mes informations"}
        </Button>
        <Button variant="outline" className="w-full" onClick={() => navigate("/profile/info")}>
          Modifier
        </Button>
        <p className="text-[10px] text-muted-foreground text-center">
          Aucune information n'est partagée. Cette étape met simplement à jour la date de vérification.
        </p>
      </Card>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3 p-3">
      <span className="text-muted-foreground text-xs uppercase tracking-wider">{label}</span>
      <span className="text-sm font-medium text-right break-all">{value}</span>
    </div>
  );
}