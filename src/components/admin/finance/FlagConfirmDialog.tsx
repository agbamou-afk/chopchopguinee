import { useEffect, useState } from "react";
import { AlertTriangle } from "lucide-react";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

interface Props {
  pending: { key: string; label: string; value: boolean } | null;
  currentEnabled: boolean;
  saving?: boolean;
  onCancel: () => void;
  onConfirm: (reason: string) => void;
}

/**
 * Financially consequential flags cannot be flipped without an explicit
 * confirmation and a human-entered reason. The write itself goes through
 * `admin_set_feature_flag` (God Admin only, audited).
 */
export function FlagConfirmDialog({ pending, currentEnabled, saving, onCancel, onConfirm }: Props) {
  const [reason, setReason] = useState("");
  useEffect(() => { if (pending) setReason(""); }, [pending]);

  return (
    <Dialog open={!!pending} onOpenChange={(v) => { if (!v && !saving) onCancel(); }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{pending?.value ? "Activer" : "Désactiver"} — {pending?.label}</DialogTitle>
          <DialogDescription>
            Capacité financière conséquente. Le changement prend effet immédiatement pour les
            nouvelles transactions et n'affecte aucune transaction déjà acceptée.
          </DialogDescription>
        </DialogHeader>
        <div className="rounded-md border p-2 text-xs font-mono">
          {pending?.key} :{" "}
          <span className="line-through opacity-60">{currentEnabled ? "actif" : "inactif"}</span>
          {" → "}
          <span className="font-semibold">{pending?.value ? "actif" : "inactif"}</span>
        </div>
        <div className="flex items-start gap-2 text-[11px] text-muted-foreground">
          <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
          Enregistré dans le journal d'audit (auteur, horodatage, avant/après).
        </div>
        <div>
          <Label className="text-xs" htmlFor="flag-reason-fin">Motif (obligatoire)</Label>
          <Textarea id="flag-reason-fin" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={saving} onClick={onCancel}>Annuler</Button>
          <Button disabled={saving || reason.trim().length < 5} onClick={() => onConfirm(reason.trim())}>
            {saving ? "Enregistrement…" : "Confirmer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}