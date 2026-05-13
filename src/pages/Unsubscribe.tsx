import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Loader2, CheckCircle2, AlertCircle } from "lucide-react";

type State = "loading" | "valid" | "already" | "invalid" | "submitting" | "done" | "error";

export default function Unsubscribe() {
  const [params] = useSearchParams();
  const token = params.get("token");
  const [state, setState] = useState<State>("loading");

  useEffect(() => {
    if (!token) { setState("invalid"); return; }
    const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/handle-email-unsubscribe?token=${encodeURIComponent(token)}`;
    fetch(url, { headers: { apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY } })
      .then(r => r.json())
      .then(data => {
        if (data.valid) setState("valid");
        else if (data.reason === "already_unsubscribed") setState("already");
        else setState("invalid");
      })
      .catch(() => setState("error"));
  }, [token]);

  const confirm = async () => {
    if (!token) return;
    setState("submitting");
    const { data, error } = await supabase.functions.invoke("handle-email-unsubscribe", { body: { token } });
    if (error || !data?.success) setState(data?.reason === "already_unsubscribed" ? "already" : "error");
    else setState("done");
  };

  return (
    <main className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="max-w-md w-full p-8 text-center space-y-4">
        <h1 className="text-xl font-bold">Désabonnement CHOP CHOP</h1>
        {state === "loading" && <Loader2 className="w-8 h-8 mx-auto animate-spin text-primary" />}
        {state === "valid" && (
          <>
            <p className="text-muted-foreground">Confirmez le désabonnement des e-mails marketing CHOP CHOP. Vous continuerez à recevoir les e-mails essentiels (sécurité, paiements, courses).</p>
            <Button onClick={confirm} className="w-full">Confirmer le désabonnement</Button>
          </>
        )}
        {state === "submitting" && <Loader2 className="w-8 h-8 mx-auto animate-spin text-primary" />}
        {state === "done" && (
          <>
            <CheckCircle2 className="w-10 h-10 mx-auto text-primary" />
            <p>Vous êtes désabonné. Merci d'avoir fait partie de CHOP CHOP.</p>
          </>
        )}
        {state === "already" && (
          <>
            <CheckCircle2 className="w-10 h-10 mx-auto text-primary" />
            <p>Vous êtes déjà désabonné.</p>
          </>
        )}
        {(state === "invalid" || state === "error") && (
          <>
            <AlertCircle className="w-10 h-10 mx-auto text-destructive" />
            <p className="text-muted-foreground">Lien invalide ou expiré. Contactez support@chopchopguinee.com pour assistance.</p>
          </>
        )}
      </Card>
    </main>
  );
}