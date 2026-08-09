import { useState } from "react";
import { AlertTriangle } from "lucide-react";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { DiffEntry, FIELD_LABELS, formatFieldValue } from "@/lib/admin/financePolicy";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  title: string;
  effectiveFrom: string;
  diff: DiffEntry[];
  saving?: boolean;
  onConfirm: (reason: string) => void;
}

/**
 * Before/after diff + mandatory reason. Nothing is written until the God Admin
 * confirms here; the reason is stored on the policy row and in the audit log.
 */
export function PolicyConfirmDialog({
  open, onOpenChange, title, effectiveFrom, diff, saving, onConfirm,
}: Props) {
  const [reason, setReason] = useState("");
  return (
    <Dialog open={open} onOpenChange={(v) => { if (!saving) { onOpenChange(v); if (!v) setReason(""); } }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            Applicable uniquement aux transactions futures, à partir du {effectiveFrom}.
            Les missions déjà acceptées conservent leur instantané de politique.
          </DialogDescription>
        </DialogHeader>

        {diff.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune modification détectée.</p>
        ) : (
          <div className="rounded-md border divide-y max-h-64 overflow-auto">
            {diff.map((d) => (
              <div key={d.field} className="p-2 text-xs flex items-center justify-between gap-3">
                <span className="text-muted-foreground">
                  {d.label ?? FIELD_LABELS[d.field as keyof typeof FIELD_LABELS] ?? d.field}
                </span>
                <span className="font-mono">
                  <span className="line-through opacity-60">
                    {(d.format ?? ((v: unknown) => formatFieldValue(d.field, v)))(d.before)}
                  </span>
                  {" → "}
                  <span className="font-semibold">
                    {(d.format ?? ((v: unknown) => formatFieldValue(d.field, v)))(d.after)}
                  </span>
                </span>
              </div>
            ))}
          </div>
        )}

        <div className="flex items-start gap-2 text-[11px] text-muted-foreground">
          <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
          Cette action est enregistrée dans le journal d'audit (auteur, horodatage, avant/après).
        </div>

        <div>
          <Label className="text-xs" htmlFor="policy-reason">Motif (obligatoire)</Label>
          <Textarea
            id="policy-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Ex. décision comité tarifaire du 12/08"
            rows={3}
          />
        </div>

        <DialogFooter>
          <Button variant="outline" disabled={saving} onClick={() => onOpenChange(false)}>Annuler</Button>
          <Button
            disabled={saving || diff.length === 0 || reason.trim().length < 5}
            onClick={() => onConfirm(reason.trim())}
          >
            {saving ? "Enregistrement…" : "Confirmer et programmer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
