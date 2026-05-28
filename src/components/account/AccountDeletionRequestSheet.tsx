import { useState } from "react";
import { AlertTriangle, Loader2, ShieldCheck } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { useAuth } from "@/contexts/AuthContext";
import { createSupportIssue } from "@/lib/support/issues";
import { toast } from "@/hooks/use-toast";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * Pilot-safe account-deletion entry point required for App Store / Play Store
 * submission. Creates a support_issue of type `account_issue` tagged with
 * `metadata.kind = "account_deletion_request"` so admins can process it
 * manually during the pilot. Never hard-deletes wallet, payment, support,
 * or order records.
 */
export function AccountDeletionRequestSheet({ open, onOpenChange }: Props) {
  const { user, profile } = useAuth();
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const submit = async () => {
    if (!user) {
      toast({
        title: "Connectez-vous d'abord",
        description: "Vous devez être connecté pour demander la suppression.",
      });
      return;
    }
    setSubmitting(true);
    try {
      const issue = await createSupportIssue({
        type: "account_issue",
        title: "Demande de suppression de compte",
        description: reason.trim() || null,
        severity: "medium",
        assignedRole: "admin",
        metadata: {
          kind: "account_deletion_request",
          requested_at: new Date().toISOString(),
          email: user.email ?? null,
          phone: profile?.phone ?? null,
          user_id: user.id,
        },
      });
      Analytics.track("account.deletion.requested", {
        metadata: { ok: !!issue, issue_id: issue?.id ?? null },
      });
      if (!issue) {
        toast({
          title: "Demande non envoyée",
          description:
            "Nous n'avons pas pu enregistrer votre demande. Réessayez ou contactez support@chopchopguinee.com.",
        });
        return;
      }
      setSubmitted(true);
      toast({
        title: "Demande reçue",
        description: "Notre équipe vous contactera sous peu.",
      });
    } finally {
      setSubmitting(false);
    }
  };

  const close = () => {
    onOpenChange(false);
    // Reset for next opening
    setTimeout(() => {
      setSubmitted(false);
      setReason("");
    }, 250);
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="bottom"
        className="max-w-md mx-auto rounded-t-3xl max-h-[85vh] overflow-y-auto"
      >
        <SheetHeader className="text-left">
          <SheetTitle className="flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-destructive" />
            {submitted ? "Demande enregistrée" : "Demander la suppression du compte"}
          </SheetTitle>
          <SheetDescription className="text-[13px] leading-snug text-muted-foreground">
            {submitted
              ? "Notre équipe support va examiner votre demande. Vous recevrez une confirmation par email ou téléphone."
              : "Vous pouvez demander la suppression de votre compte. Certaines informations peuvent être conservées si nécessaire pour la sécurité, les paiements, la prévention de la fraude ou les obligations légales."}
          </SheetDescription>
        </SheetHeader>

        {!submitted ? (
          <div className="mt-4 space-y-4">
            <div className="rounded-2xl border border-border/60 bg-muted/30 p-3 flex gap-3">
              <ShieldCheck className="w-5 h-5 text-primary shrink-0 mt-0.5" />
              <p className="text-[12.5px] leading-snug text-muted-foreground">
                Pendant la phase pilote, les demandes sont traitées manuellement par notre équipe sous 7 jours ouvrés.
              </p>
            </div>
            <div>
              <label className="text-[12px] font-semibold text-foreground mb-1.5 block">
                Raison (facultatif)
              </label>
              <Textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Aidez-nous à améliorer CHOPCHOP…"
                rows={3}
                maxLength={500}
              />
            </div>
            <SheetFooter className="gap-2 sm:gap-2">
              <Button variant="outline" onClick={close} disabled={submitting}>
                Annuler
              </Button>
              <Button
                variant="destructive"
                onClick={submit}
                disabled={submitting || !user}
                className="gap-2"
              >
                {submitting && <Loader2 className="w-4 h-4 animate-spin" />}
                Confirmer la demande
              </Button>
            </SheetFooter>
          </div>
        ) : (
          <div className="mt-6">
            <Button className="w-full" onClick={close}>
              Fermer
            </Button>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}