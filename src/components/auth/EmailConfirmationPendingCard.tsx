import { useState } from "react";
import { Loader2, MailCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { BrandLogo } from "@/components/brand/BrandLogo";

type Intent = "client" | "driver" | "merchant";

export interface EmailConfirmationPendingCardProps {
  email: string;
  intent: Intent;
  onAlreadyConfirmed: () => void;
  onUseAnotherEmail: () => void;
}

export function EmailConfirmationPendingCard({
  email,
  intent,
  onAlreadyConfirmed,
  onUseAnotherEmail,
}: EmailConfirmationPendingCardProps) {
  const [busy, setBusy] = useState(false);

  const resend = async () => {
    setBusy(true);
    const { error } = await supabase.auth.resend({
      type: "signup",
      email,
      options: { emailRedirectTo: `${window.location.origin}/` },
    });
    setBusy(false);
    if (error) {
      toast({
        title: "Échec",
        description: "Impossible de renvoyer l'email pour le moment. Réessayez.",
      });
      return;
    }
    toast({
      title: "Email de confirmation renvoyé",
      description: "Vérifiez votre boîte de réception et vos spams.",
    });
  };

  return (
    <div className="w-full max-w-sm bg-card rounded-3xl shadow-elevated p-6">
      <div className="flex flex-col items-center mb-5">
        <BrandLogo size="lg" className="mb-3" />
        <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mb-3">
          <MailCheck className="w-6 h-6 text-primary" />
        </div>
        <h1 className="text-lg font-semibold text-foreground">Vérifiez votre email</h1>
      </div>

      <p className="text-sm text-muted-foreground text-center">
        Nous avons envoyé un email de confirmation à :
      </p>
      <p className="text-sm font-semibold text-foreground text-center mt-1 break-all">
        {email}
      </p>

      <p className="text-[13px] text-muted-foreground text-center mt-3 leading-relaxed">
        Cliquez sur le lien dans cet email pour activer votre compte CHOPCHOP.
        Pensez à vérifier vos spams ou promotions.
      </p>

      {intent === "driver" && (
        <p className="text-[12px] text-foreground bg-primary/5 border border-primary/20 rounded-xl p-3 mt-4 leading-relaxed">
          Après confirmation, vous pourrez finaliser votre demande chauffeur/coursier.
        </p>
      )}

      <p className="text-[11px] text-muted-foreground text-center mt-4 leading-relaxed">
        Votre email est utilisé pour votre compte et les notifications
        importantes. La vérification par téléphone sera ajoutée prochainement.
      </p>

      <div className="mt-5 space-y-2">
        <Button
          type="button"
          onClick={resend}
          disabled={busy}
          className="w-full h-12 gradient-primary"
        >
          {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : "Renvoyer l'email"}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={onAlreadyConfirmed}
          className="w-full h-11"
        >
          J'ai déjà confirmé mon compte
        </Button>
        <button
          type="button"
          onClick={onUseAnotherEmail}
          className="block w-full text-[12px] text-muted-foreground hover:text-foreground text-center pt-1 underline"
        >
          Utiliser une autre adresse email
        </button>
      </div>
    </div>
  );
}