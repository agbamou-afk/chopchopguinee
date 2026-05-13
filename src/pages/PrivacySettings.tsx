import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, ShieldCheck, Sparkles, MapPin, Megaphone, Lock } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import { Seo } from "@/components/Seo";
import { supabase } from "@/integrations/supabase/client";
import { Consent, type TConsentState } from "@/lib/analytics/consent";

const ROWS: Array<{
  key: keyof Omit<TConsentState, "security_fraud">;
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  body: string;
}> = [
  {
    key: "basic_analytics",
    icon: Sparkles,
    title: "Analytique de base",
    body: "Nous aide à comprendre comment l'app est utilisée pour améliorer la fiabilité, le temps de chargement et la qualité du service.",
  },
  {
    key: "personalization",
    icon: ShieldCheck,
    title: "Recommandations personnalisées",
    body: "Suggestions de courses, repas et annonces basées sur votre activité dans l'app. Aucun profilage publicitaire.",
  },
  {
    key: "location_improvements",
    icon: MapPin,
    title: "Amélioration par zone",
    body: "Permet d'utiliser votre quartier (Kaloum, Kipé, Madina…) pour améliorer la disponibilité des chauffeurs et des livraisons. Jamais de localisation précise en arrière-plan.",
  },
  {
    key: "marketing_analytics",
    icon: Megaphone,
    title: "Analytique marketing",
    body: "Mesure l'efficacité de nos campagnes (par ex. quels services vous découvrez via une promo).",
  },
];

export default function PrivacySettings() {
  const navigate = useNavigate();
  const [state, setState] = useState<TConsentState>(Consent.current());
  const [userId, setUserId] = useState<string | null>(null);
  const [saving, setSaving] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      const uid = data.session?.user.id ?? null;
      setUserId(uid);
      if (uid) {
        const next = await Consent.loadForUser(uid);
        setState(next);
      }
    });
    return Consent.subscribe(setState);
  }, []);

  async function toggle(key: keyof Omit<TConsentState, "security_fraud">) {
    const next = !state[key];
    setSaving(key);
    try {
      await Consent.save(userId, { [key]: next });
      toast({ title: "Préférence enregistrée" });
    } catch (e) {
      toast({ title: "Erreur", description: "Impossible de sauvegarder.", variant: "destructive" });
    } finally {
      setSaving(null);
    }
  }

  return (
    <div className="min-h-screen bg-background">
      <Seo title="Confidentialité — CHOP CHOP" description="Vos préférences d'analyse et de personnalisation." canonical="/profile/privacy" />
      <header className="sticky top-0 z-10 bg-background border-b border-border/60">
        <div className="max-w-md mx-auto h-14 flex items-center gap-2 px-3">
          <Button size="icon" variant="ghost" onClick={() => navigate(-1)} aria-label="Retour">
            <ArrowLeft className="w-5 h-5" />
          </Button>
          <h1 className="text-base font-semibold">Confidentialité</h1>
        </div>
      </header>

      <main className="max-w-md mx-auto px-4 py-5 space-y-4 pb-20">
        <p className="text-sm text-muted-foreground leading-relaxed">
          CHOP CHOP collecte des signaux opérationnels pour améliorer les courses, les livraisons,
          le marché, la sécurité du portefeuille et la protection contre la fraude. Vous décidez
          ce que vous partagez.
        </p>

        {ROWS.map(({ key, icon: Icon, title, body }) => (
          <Card key={key} className="p-4 rounded-2xl shadow-soft border-border/60">
            <div className="flex items-start gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                <Icon className="w-5 h-5 text-primary" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <h2 className="text-sm font-semibold text-foreground">{title}</h2>
                  <Switch
                    checked={state[key]}
                    disabled={saving === key}
                    onCheckedChange={() => toggle(key)}
                  />
                </div>
                <p className="text-xs text-muted-foreground mt-1 leading-relaxed">{body}</p>
              </div>
            </div>
          </Card>
        ))}

        <Card className="p-4 rounded-2xl border-primary/20 bg-primary/5">
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-xl bg-primary/15 flex items-center justify-center shrink-0">
              <Lock className="w-5 h-5 text-primary" />
            </div>
            <div className="flex-1">
              <h2 className="text-sm font-semibold text-foreground">Sécurité & fraude (toujours actif)</h2>
              <p className="text-xs text-muted-foreground mt-1 leading-relaxed">
                Pour protéger votre compte, votre portefeuille et la communauté, nous enregistrons
                en permanence les signaux de sécurité essentiels (tentatives de connexion, échecs
                de PIN, transactions inhabituelles). Ces signaux ne peuvent pas être désactivés.
              </p>
            </div>
          </div>
        </Card>

        <p className="text-[11px] text-muted-foreground/80 text-center pt-2">
          Aucune donnée n'est vendue. Aucun message privé n'est utilisé pour entraîner l'IA.
        </p>
      </main>
    </div>
  );
}