import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { REPORT_REASONS } from "@/lib/marche";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";

export function ReportModal({
  listingId,
  open,
  onOpenChange,
}: {
  listingId: string;
  open: boolean;
  onOpenChange: (v: boolean) => void;
}) {
  const [reason, setReason] = useState(REPORT_REASONS[0].id);
  const [details, setDetails] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    const { data: sess } = await supabase.auth.getSession();
    if (!sess.session) {
      toast({ title: "Connexion requise", description: "Connectez-vous pour signaler." });
      setBusy(false);
      return;
    }
    const { error } = await supabase.from("listing_reports").insert({
      listing_id: listingId,
      reporter_id: sess.session.user.id,
      reason,
      details: details.slice(0, 500) || null,
    });
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    toast({ title: "Signalement envoyé", description: "Merci, notre équipe va examiner cette annonce." });
    onOpenChange(false);
    setDetails("");
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Signaler cette annonce</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            {REPORT_REASONS.map((r) => (
              <button
                key={r.id}
                onClick={() => setReason(r.id)}
                className={`px-3 py-2 rounded-xl text-sm border ${
                  reason === r.id ? "bg-primary text-primary-foreground border-primary" : "bg-card border-border"
                }`}
              >
                {r.label}
              </button>
            ))}
          </div>
          <Textarea
            placeholder="Détails (optionnel, 500 max)"
            maxLength={500}
            value={details}
            onChange={(e) => setDetails(e.target.value)}
          />
          <Button onClick={submit} disabled={busy} className="w-full">
            {busy ? "Envoi…" : "Envoyer le signalement"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}