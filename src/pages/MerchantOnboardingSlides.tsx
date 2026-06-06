import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ShoppingBag, Boxes, ShieldCheck, MapPin, ArrowRight } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Seo } from "@/components/Seo";

const SLIDES = [
  {
    icon: ShoppingBag,
    title: "Vendez sur CHOPCHOP Marché",
    body: "Créez votre boutique, ajoutez vos produits et touchez plus de clients autour de vous.",
  },
  {
    icon: Boxes,
    title: "Préparez votre catalogue",
    body: "Ajoutez vos produits, photos, prix et quantités. Vous pouvez préparer votre boutique pendant la vérification.",
  },
  {
    icon: ShieldCheck,
    title: "Vérification marchand",
    body: "Pour protéger les clients et les marchands, CHOPCHOP vérifie chaque boutique avant sa visibilité complète.",
  },
  {
    icon: MapPin,
    title: "Votre position compte",
    body: "Indiquez l’emplacement exact de votre boutique pour faciliter les commandes, retraits et livraisons.",
  },
];

export default function MerchantOnboardingSlides() {
  const navigate = useNavigate();
  const { user, ready, isLoggedIn } = useAuth();
  const [i, setI] = useState(0);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (ready && !isLoggedIn) navigate("/auth", { replace: true });
  }, [ready, isLoggedIn, navigate]);

  const finish = async () => {
    if (!user) return;
    setBusy(true);
    try {
      await (supabase as any).from("user_preferences").upsert(
        { user_id: user.id, merchant_slides_completed_at: new Date().toISOString(), app_mode: "merchant" },
        { onConflict: "user_id" },
      );
    } catch { /* noop */ }
    navigate("/merchant/onboarding", { replace: true });
  };

  const next = () => {
    if (i < SLIDES.length - 1) setI((v) => v + 1);
    else void finish();
  };

  const S = SLIDES[i];
  const Icon = S.icon;

  return (
    <div className="min-h-screen flex flex-col bg-background">
      <Seo title="Devenir marchand — CHOPCHOP" description="Découvrez comment vendre sur CHOPCHOP Marché." canonical="/merchant/onboarding-slides" />
      <div className="flex-1 flex items-center justify-center px-6">
        <div className="w-full max-w-sm text-center">
          <div className="mx-auto w-20 h-20 rounded-3xl gradient-primary flex items-center justify-center mb-6 shadow-elegant">
            <Icon className="w-10 h-10 text-primary-foreground" />
          </div>
          <h1 className="text-2xl font-extrabold text-foreground mb-3">{S.title}</h1>
          <p className="text-sm text-muted-foreground leading-relaxed">{S.body}</p>
        </div>
      </div>
      <div className="px-6 pb-8 max-w-sm mx-auto w-full">
        <div className="flex items-center justify-center gap-2 mb-5">
          {SLIDES.map((_, idx) => (
            <span
              key={idx}
              className={`h-1.5 rounded-full transition-all ${idx === i ? "w-6 bg-primary" : "w-2 bg-border"}`}
            />
          ))}
        </div>
        <Button onClick={next} disabled={busy} className="w-full h-12 text-base">
          {i === SLIDES.length - 1 ? "Créer ma boutique" : "Suivant"}
          <ArrowRight className="w-4 h-4 ml-2" />
        </Button>
        {i < SLIDES.length - 1 && (
          <button type="button" onClick={() => void finish()} className="w-full mt-3 text-xs text-muted-foreground">
            Passer
          </button>
        )}
      </div>
    </div>
  );
}
