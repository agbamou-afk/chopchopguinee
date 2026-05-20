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

const REASONS = [
  "Restaurant introuvable",
  "Commande non prête",
  "Client injoignable",
  "Adresse incorrecte",
  "Problème moto",
  "Autre",
] as const;

interface MissionIssueSheetProps {
  missionId: string;
  open: boolean;
  onOpenChange: (o: boolean) => void;
  onReported?: (m: Mission) => void;
}

export function MissionIssueSheet({ missionId, open, onOpenChange, onReported }: MissionIssueSheetProps) {
  const [reason, setReason] = useState<string | null>(null);
  const [extra, setExtra] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (!reason || busy) return;
    setBusy(true);
    try {
      const note = extra.trim() ? `${reason} — ${extra.trim()}` : reason;
      const updated = await reportIssue(missionId, note);
      onReported?.(updated);
      toast.success("Problème signalé à CHOP CHOP");
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
            Choisissez le motif. CHOP CHOP prend le relais.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 grid grid-cols-2 gap-2">
          {REASONS.map((r) => {
            const active = reason === r;
            return (
              <button
                key={r}
                type="button"
                onClick={() => setReason(r)}
                className={`text-left text-sm font-medium rounded-xl px-3 py-2.5 border transition-colors ${
                  active
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-border bg-card hover:bg-muted"
                }`}
              >
                {r}
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
          Mission suivie par CHOP CHOP · Confirmation requise à chaque étape
        </p>
      </SheetContent>
    </Sheet>
  );
}