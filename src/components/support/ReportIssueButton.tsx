import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { LifeBuoy, Loader2 } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import { createSupportIssue, type CreateIssueInput } from "@/lib/support/issues";
import {
  ISSUE_TYPE_LABEL,
  type IssueType,
} from "@/lib/support/constants";

/**
 * Reusable "Signaler un problème" entry point.
 *
 * Calm, non-blocking. Wraps `createSupportIssue` (never-throw) and shows a
 * single confirmation toast. Never mutates payment/order state.
 */
export interface ReportIssueButtonProps {
  /** Allowed issue types for this surface. */
  issueTypes: IssueType[];
  /** Pre-bound context (payment intent id, food order id, mission id, ...). */
  context: Omit<CreateIssueInput, "type" | "description">;
  /** Optional button label override. */
  label?: string;
  /** Optional className for layout. */
  className?: string;
  variant?: "outline" | "ghost" | "secondary";
}

export function ReportIssueButton({
  issueTypes,
  context,
  label = "Signaler un problème",
  className,
  variant = "outline",
}: ReportIssueButtonProps) {
  const [open, setOpen] = useState(false);
  const [type, setType] = useState<IssueType>(issueTypes[0]);
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    setSubmitting(true);
    const row = await createSupportIssue({
      ...context,
      type,
      description: description.trim() || null,
    });
    setSubmitting(false);
    setOpen(false);
    setDescription("");
    if (row) {
      toast({
        title: "Demande envoyée",
        description: "Votre demande support a été reçue.",
      });
    } else {
      toast({
        title: "Connexion requise",
        description: "Connectez-vous pour signaler ce problème.",
      });
    }
  };

  return (
    <>
      <Button
        type="button"
        variant={variant}
        className={className}
        onClick={() => setOpen(true)}
      >
        <LifeBuoy className="w-4 h-4 mr-2" />
        {label}
      </Button>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="bottom" className="rounded-t-3xl">
          <SheetHeader className="text-left">
            <SheetTitle>Signaler un problème</SheetTitle>
            <SheetDescription>
              Notre équipe support sera notifiée. Aucune action n'est prise sur
              votre paiement ou votre commande.
            </SheetDescription>
          </SheetHeader>
          <div className="mt-4 space-y-3">
            <div className="grid gap-2">
              {issueTypes.map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setType(t)}
                  className={`text-left px-3 py-2 rounded-xl border text-sm transition-colors ${
                    type === t
                      ? "border-primary bg-primary/10 text-foreground"
                      : "border-border bg-card text-muted-foreground hover:text-foreground"
                  }`}
                >
                  {ISSUE_TYPE_LABEL[t]}
                </button>
              ))}
            </div>
            <Textarea
              placeholder="Décrivez le problème (optionnel)"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={3}
            />
            <Button
              className="w-full"
              onClick={submit}
              disabled={submitting}
            >
              {submitting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Envoyer
            </Button>
          </div>
        </SheetContent>
      </Sheet>
    </>
  );
}