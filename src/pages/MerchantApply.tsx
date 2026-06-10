import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import {
  Store,
  ShoppingBag,
  ShieldCheck,
  Wallet as WalletIcon,
  MessageCircle,
  Sparkles,
  CheckCircle2,
  ArrowRight,
  ListChecks,
  MapPin,
  Camera,
  IdCard,
  Loader2,
} from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Seo } from "@/components/Seo";
import { BrandLogo } from "@/components/brand/BrandLogo";
import {
  MERCHANT_HUB_PATH,
  MERCHANT_ONBOARDING_PATH,
  storeMerchantIntent,
  resolveMerchantPostAuthRoute,
} from "@/lib/merchantRouting";

/**
 * Public merchant acquisition landing page. Parallel to the driver branch.
 * - Logged-out: explains Marché, CTA → /auth?intent=merchant&next=/merchant/onboarding
 * - Logged-in:  CTA → /merchant/hub (if store exists) or /merchant/onboarding
 */
export default function MerchantApply() {
  const navigate = useNavigate();
  const { ready, isLoggedIn, user } = useAuth();
  const [resolving, setResolving] = useState(false);

  // Pre-stamp merchant intent so a refresh or email-confirmation roundtrip
  // does not drop the branch.
  useEffect(() => {
    storeMerchantIntent();
  }, []);

  const onPrimary = async () => {
    if (!ready) return;
    storeMerchantIntent();
    if (!isLoggedIn || !user) {
      navigate(
        "/auth?mode=signup&intent=merchant&branch=merchant&next=/merchant/onboarding",
      );
      return;
    }
    setResolving(true);
    try {
      const route = await resolveMerchantPostAuthRoute(user.id);
      navigate(route, { replace: true });
    } catch {
      navigate(MERCHANT_ONBOARDING_PATH, { replace: true });
    } finally {
      setResolving(false);
    }
  };

  const onSecondary = () => {
    storeMerchantIntent();
    navigate("/auth?intent=merchant&branch=merchant&next=/merchant/onboarding");
  };

  return (
    <div className="min-h-screen bg-background">
      <Seo
        title="Devenir marchand — CHOPCHOP Marché"
        description="Vendez avec CHOPCHOP. Créez votre boutique, ajoutez vos produits, recevez des demandes clients et développez votre activité locale à Conakry."
        canonical="/merchant/apply"
      />

      {/* Hero */}
      <header
        className="relative overflow-hidden bg-gradient-to-br from-primary/15 via-background to-background"
        style={{ paddingTop: "max(1.25rem, env(safe-area-inset-top))" }}
      >
        <div className="max-w-md mx-auto px-5 pt-3 pb-8">
          <div className="flex items-center justify-between mb-6">
            <BrandLogo size="sm" />
            <Link
              to="/auth?intent=merchant&branch=merchant&next=/merchant/onboarding"
              className="text-xs font-semibold text-primary hover:underline"
            >
              J'ai déjà un compte
            </Link>
          </div>
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-primary/15 text-primary text-[11px] font-semibold uppercase tracking-wider mb-3">
            <Sparkles className="w-3 h-3" /> CHOPCHOP Marché
          </div>
          <h1 className="text-3xl font-extrabold leading-tight text-foreground">
            Vendez avec CHOPCHOP
          </h1>
          <p className="text-sm text-muted-foreground mt-3 leading-relaxed">
            Créez votre boutique, ajoutez vos produits, recevez des demandes
            clients et développez votre activité locale.
          </p>
          <div className="mt-5 space-y-2">
            <Button
              onClick={onPrimary}
              disabled={resolving || !ready}
              className="w-full h-12 text-base gradient-primary"
            >
              {resolving ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <Store className="w-4 h-4 mr-2" />
              )}
              Créer ma boutique
            </Button>
            <Button
              variant="outline"
              onClick={onSecondary}
              className="w-full h-11"
            >
              J'ai déjà un compte
            </Button>
          </div>
        </div>
      </header>

      <main className="max-w-md mx-auto px-5 py-6 space-y-8">
        {/* Why join */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">
            Pourquoi rejoindre CHOPCHOP ?
          </h2>
          <ul className="space-y-2">
            {[
              { icon: ShoppingBag, title: "Plus de visibilité", body: "Apparaissez auprès des clients autour de vous." },
              { icon: MessageCircle, title: "Demandes clients", body: "Recevez des demandes par WhatsApp, appel ou livraison." },
              { icon: ListChecks, title: "Catalogue simple", body: "Ajoutez vos produits en quelques secondes." },
              { icon: WalletIcon, title: "Wallet CHOP", body: "Encaissez et suivez vos ventes en GNF." },
              { icon: ShieldCheck, title: "Accompagnement terrain", body: "Une équipe locale pour vous aider à démarrer." },
            ].map(({ icon: Icon, title, body }) => (
              <li
                key={title}
                className="flex items-start gap-3 p-3 rounded-2xl border border-border/60 bg-card"
              >
                <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                  <Icon className="w-5 h-5 text-primary" />
                </div>
                <div className="min-w-0">
                  <p className="font-semibold text-foreground text-sm">{title}</p>
                  <p className="text-xs text-muted-foreground">{body}</p>
                </div>
              </li>
            ))}
          </ul>
        </section>

        {/* How it works */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">
            Comment ça marche ?
          </h2>
          <ol className="space-y-2">
            {[
              "Créez votre boutique",
              "Ajoutez vos produits",
              "Complétez la vérification",
              "Recevez des demandes",
              "Vendez et gérez votre activité",
            ].map((step, i) => (
              <li
                key={step}
                className="flex items-center gap-3 p-3 rounded-2xl border border-border/60 bg-card"
              >
                <div className="w-8 h-8 rounded-full bg-primary text-primary-foreground text-sm font-bold flex items-center justify-center shrink-0">
                  {i + 1}
                </div>
                <p className="text-sm font-medium text-foreground">{step}</p>
                <ArrowRight className="w-4 h-4 text-muted-foreground ml-auto" />
              </li>
            ))}
          </ol>
        </section>

        {/* What you'll need */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">
            Ce dont vous avez besoin
          </h2>
          <div className="rounded-2xl border border-border/60 bg-card p-4 space-y-2">
            {[
              { icon: Store, label: "Nom de boutique", required: true },
              { icon: MessageCircle, label: "Numéro WhatsApp", required: true },
              { icon: ListChecks, label: "Catégorie", required: true },
              { icon: MapPin, label: "Localisation", required: true },
              { icon: Camera, label: "Photo de boutique", required: false },
              { icon: IdCard, label: "Pièce d'identité", required: false },
            ].map(({ icon: Icon, label, required }) => (
              <div key={label} className="flex items-center gap-3 text-sm">
                <Icon className="w-4 h-4 text-muted-foreground" />
                <span className="flex-1 text-foreground">{label}</span>
                <span
                  className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${
                    required
                      ? "bg-primary/10 text-primary"
                      : "bg-muted text-muted-foreground"
                  }`}
                >
                  {required ? "Requis" : "Plus tard"}
                </span>
              </div>
            ))}
          </div>
          <p className="text-[11px] text-muted-foreground mt-3 leading-relaxed">
            La validation protège les clients et les marchands. Vous pouvez
            préparer votre catalogue pendant la vérification.
          </p>
        </section>

        {/* Trust footer */}
        <section className="rounded-2xl bg-primary/5 border border-primary/20 p-4 flex items-start gap-3">
          <CheckCircle2 className="w-5 h-5 text-primary shrink-0 mt-0.5" />
          <p className="text-xs text-foreground leading-relaxed">
            Rejoindre CHOPCHOP est gratuit. Aucun engagement, vous gardez le
            contrôle de votre boutique et de votre catalogue.
          </p>
        </section>

        <div className="pt-2">
          <Button
            onClick={onPrimary}
            disabled={resolving || !ready}
            className="w-full h-12 text-base gradient-primary"
          >
            {resolving ? (
              <Loader2 className="w-4 h-4 mr-2 animate-spin" />
            ) : (
              <Store className="w-4 h-4 mr-2" />
            )}
            Créer ma boutique
          </Button>
        </div>
      </main>
    </div>
  );
}