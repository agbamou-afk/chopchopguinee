import { useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { reportIssue } from "@/lib/missions/missions";
import { toast } from "sonner";
import type { Mission } from "@/lib/missions/types";
import { createSupportIssue } from "@/lib/support/issues";
import type { IssueType } from "@/lib/support/constants";

/**
 * Driver issue reasons, mapped to support_issues.issue_type so the
 * operational log captures a structured type without changing the
 * mission-side reportIssue contract.
 */
const REASONS: { label: string; type: IssueType }[] = [
  { label: "Restaurant introuvable", type: "merchant_not_ready" },
  { label: "Commande non prête", type: "merchant_not_ready" },
  { label: "Client injoignable", type: "customer_unreachable" },
  { label: "Adresse incorrecte", type: "wrong_address" },
  { label: "Problème moto", type: "app_bug" },
  { label: "Autre", type: "other" },
];

interface MissionIssueSheetProps {
  missionId: string;
  open: boolean;
  onOpenChange: (o: boolean) => void;
  onReported?: (m: Mission) => void;
}

export function MissionIssueSheet({ missionId, open, onOpenChange, onReported }: MissionIssueSheetProps) {
  const [reason, setReason] = useState<typeof REASONS[number] | null>(null);
  const [extra, setExtra] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (!reason || busy) return;
    setBusy(true);
    try {
      const note = extra.trim() ? `${reason.label} — ${extra.trim()}` : reason.label;
      const updated = await reportIssue(missionId, note);
      onReported?.(updated);
      // Mirror to support_issues. Never-throw — must not break mission flow.
      await createSupportIssue({
        type: reason.type,
        title: reason.label,
        description: extra.trim() || null,
        relatedMissionId: missionId,
        district: (updated as any)?.issue_district ?? null,
        relatedDriverId: (updated as any)?.courier_id ?? null,
        relatedCustomerId: (updated as any)?.customer_id ?? null,
        metadata: { source: "driver_issue_sheet" },
      });
      toast.success("Problème signalé à CHOPCHOP");
      onOpenChange(false);
      setReason(null);
      setExtra("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl pb-8 max-h-[80vh] overflow-y-auto">
        <SheetHeader className="text-left">
          <SheetTitle className="flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-destructive" />
            Signaler un problème
          </SheetTitle>
          <SheetDescription>
            Choisissez le motif. CHOPCHOP prend le relais.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 grid grid-cols-2 gap-2">
          {REASONS.map((r) => {
            const active = reason?.label === r.label;
            return (
              <button
                key={r.label}
                type="button"
                onClick={() => setReason(r)}
                className={`text-left text-sm font-medium rounded-xl px-3 py-2.5 border transition-colors ${
                  active
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-border bg-card hover:bg-muted"
                }`}
              >
                {r.label}
              </button>
            );
          })}
        </div>

        <Textarea
          value={extra}
          onChange={(e) => setExtra(e.target.value)}
          placeholder="Détail optionnel (facultatif)"
          rows={3}
          className="mt-3"
        />

        <Button
          className="w-full h-11 mt-4"
          disabled={!reason || busy}
          onClick={submit}
        >
          {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Envoyer le signalement"}
        </Button>
        <p className="text-[11px] text-muted-foreground text-center mt-2">
          Mission suivie par CHOPCHOP · Confirmation requise à chaque étape
        </p>
      </SheetContent>
    </Sheet>
  );
}