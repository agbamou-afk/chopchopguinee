import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Send, Loader2 } from "lucide-react";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Seo } from "@/components/Seo";
import { ONBOARDING_REPLAY_EVENT } from "@/components/onboarding/ClientOnboarding";
import { DRIVER_ONBOARDING_REPLAY_EVENT } from "@/components/onboarding/DriverOnboarding";
import { useAuth } from "@/contexts/AuthContext";
import { Play } from "lucide-react";

const FAQS = [
  {
    q: "Qu'est-ce que CHOPCHOP ?",
    a: "CHOPCHOP est la super-app guinéenne qui réunit transport (moto, toktok), commande de repas, marché en ligne et transferts d'argent en GNF, dans une seule application.",
  },
  {
    q: "Comment recharger mon portefeuille ?",
    a: "Rendez-vous chez un agent CHOPCHOP, donnez-lui votre numéro et le montant. Il vous enverra un code de confirmation à 6 chiffres à valider pour créditer votre solde.",
  },
  {
    q: "Comment réserver une moto ou un toktok ?",
    a: "Sur l'écran d'accueil, choisissez Moto ou Toktok, indiquez votre destination puis confirmez. Les fonds sont réservés sur votre portefeuille jusqu'à la fin de la course.",
  },
  {
    q: "Comment annuler une course ?",
    a: "Pendant le suivi de la course, appuyez sur Annuler. Les fonds réservés seront automatiquement libérés sur votre portefeuille.",
  },
  {
    q: "Comment devenir chauffeur CHOPCHOP ?",
    a: "Activez le Mode Chauffeur depuis le menu, complétez votre profil et soumettez vos documents. Notre équipe validera votre demande sous 48 heures.",
  },
  {
    q: "Comment envoyer de l'argent à un ami ?",
    a: "Dans ChopWallet, choisissez Envoyer, saisissez le numéro du destinataire et le montant. La transaction est instantanée et gratuite entre utilisateurs CHOPCHOP.",
  },
  {
    q: "Quels sont les frais de service ?",
    a: "Les transferts entre utilisateurs sont gratuits. Une commission de 15 % est prélevée sur chaque course chauffeur. Les recharges agent sont sans frais pour le client.",
  },
  {
    q: "Mon paiement n'est pas passé, que faire ?",
    a: "Vérifiez votre solde et votre connexion. Si le problème persiste, vos fonds réservés sont libérés automatiquement sous 15 minutes. Contactez-nous via le formulaire ci-dessous.",
  },
  {
    q: "Mes données sont-elles sécurisées ?",
    a: "Oui. Vos données et transactions sont chiffrées. Nous ne partageons jamais vos informations sans votre consentement, conformément à notre politique de confidentialité.",
  },
  {
    q: "Comment commander un repas ?",
    a: "Allez dans Repas, choisissez un restaurant, ajoutez vos plats au panier et confirmez. Un livreur CHOPCHOP prend en charge votre commande.",
  },
  {
    q: "Que faire si le livreur n'arrive pas ?",
    a: "Contactez directement le livreur via l'application. Si vous ne recevez pas de réponse sous 10 minutes, annulez la commande, vous serez remboursé intégralement.",
  },
  {
    q: "Comment scanner un QR code marchand ?",
    a: "Appuyez sur le bouton scan central, pointez l'appareil photo vers le QR du marchand et confirmez le montant pour payer.",
  },
  {
    q: "Puis-je utiliser CHOPCHOP hors connexion ?",
    a: "Une connexion Internet est requise pour la plupart des fonctions (paiements, courses, livraisons). Certaines pages restent consultables hors-ligne.",
  },
  {
    q: "Comment supprimer mon compte ?",
    a: "Envoyez-nous une demande via le formulaire de contact ci-dessous. Votre compte sera fermé sous 7 jours, après vérification du solde de votre portefeuille.",
  },
  {
    q: "Quelles villes sont couvertes ?",
    a: "CHOPCHOP est actuellement disponible à Conakry et s'étend progressivement aux autres grandes villes de Guinée (Kankan, Kindia, N'Zérékoré).",
  },
];

export default function Help() {
  const navigate = useNavigate();
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const { roles } = useAuth();
  const isDriverDesignated =
    roles.includes("driver") || (roles as string[]).includes("courier");

  const replayClientOnboarding = () => {
    navigate("/?replayOnboarding=client");
  };
  const replayDriverOnboarding = () => {
    navigate("/?replayOnboarding=driver");
  };

  const sendMessage = async () => {
    const trimmed = message.trim();
    if (!trimmed) return;
    if (trimmed.length > 250) {
      toast({ title: "Message trop long", description: "250 caractères maximum." });
      return;
    }
    setSending(true);
    const { data: sess } = await supabase.auth.getSession();
    const { error } = await supabase.from("support_messages").insert({
      user_id: sess.session?.user.id ?? null,
      message: trimmed,
    });
    setSending(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    setMessage("");
    toast({ title: "Message envoyé", description: "Notre équipe vous répondra rapidement." });
  };

  return (
    <div className="min-h-screen bg-background pb-12">
      <Seo
        title="Aide et support | CHOPCHOP"
        description="Réponses aux questions fréquentes sur CHOPCHOP : recharge portefeuille, courses moto, livraison de repas, transferts d'argent et sécurité."
        canonical="/help"
        jsonLd={{
          "@context": "https://schema.org",
          "@type": "FAQPage",
          mainEntity: FAQS.map((f) => ({
            "@type": "Question",
            name: f.q,
            acceptedAnswer: { "@type": "Answer", text: f.a },
          })),
        }}
      />
      <header className="gradient-primary text-primary-foreground rounded-b-3xl px-4 pt-6 pb-8">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate(-1)} className="p-2 -ml-2 rounded-full hover:bg-white/10">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <BrandLogo size="md" loading="lazy" />
          <h1 className="text-lg font-bold">Aide & FAQ</h1>
        </div>
      </header>

      <div className="px-4 -mt-6 max-w-md mx-auto space-y-4">
        <div className="bg-card rounded-2xl shadow-card p-4">
          <h2 className="font-semibold text-foreground mb-2">Questions fréquentes</h2>
          <Accordion type="single" collapsible className="w-full">
            {FAQS.map((f, i) => (
              <AccordionItem key={i} value={`item-${i}`}>
                <AccordionTrigger className="text-left text-sm font-medium">
                  {f.q}
                </AccordionTrigger>
                <AccordionContent className="text-sm text-muted-foreground">
                  {f.a}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>

        <div className="bg-card rounded-2xl shadow-card p-4 space-y-3">
          <h2 className="font-semibold text-foreground">Revoir l'introduction</h2>
          <p className="text-xs text-muted-foreground">
            Relancez la visite guidée de CHOPCHOP à tout moment.
          </p>
          <Button variant="outline" className="w-full justify-start" onClick={replayClientOnboarding}>
            <Play className="w-4 h-4 mr-2" />
            Revoir l'introduction client
          </Button>
          {isDriverDesignated && (
            <Button variant="outline" className="w-full justify-start" onClick={replayDriverOnboarding}>
              <Play className="w-4 h-4 mr-2" />
              Revoir l'introduction chauffeur
            </Button>
          )}
        </div>

        <div className="bg-card rounded-2xl shadow-card p-5 space-y-3">
          <h2 className="font-semibold text-foreground">Contacter l'équipe</h2>
          <p className="text-xs text-muted-foreground">
            Décrivez votre problème en quelques mots. Notre équipe vous répondra par notification.
          </p>
          <Textarea
            value={message}
            onChange={(e) => setMessage(e.target.value.slice(0, 250))}
            maxLength={250}
            rows={4}
            placeholder="Votre message..."
          />
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>{message.length}/250</span>
          </div>
          <Button onClick={sendMessage} disabled={sending || !message.trim()} className="w-full">
            {sending ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Send className="w-4 h-4 mr-2" />}
            Envoyer à l'admin
          </Button>
        </div>
      </div>
    </div>
  );
}