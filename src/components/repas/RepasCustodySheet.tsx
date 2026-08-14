/**
 * R6 courier custody workflow (Repas only).
 *
 * Real proof: the photo is uploaded to the private `mission-proofs` bucket
 * before the RPC is called, and the server independently re-verifies that the
 * object exists, belongs to this courier, this mission and this phase.
 * Nothing is ever reported as "enregistrée" unless the upload truly succeeded.
 */
import { useState } from "react";
import { Camera, Check, Loader2, ShieldCheck } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { uploadMissionProof } from "@/lib/missions/proof";
import {
  confirmRepasDelivery,
  confirmRepasHandoff,
  isRefusal,
  refusalMessage,
} from "@/lib/repas/custody";

export type RepasCustodyPhase = "pickup" | "delivery";

interface Props {
  missionId: string;
  phase: RepasCustodyPhase;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirmed?: () => void;
}

const COPY: Record<RepasCustodyPhase, { title: string; desc: string; codeLabel: string }> = {
  pickup: {
    title: "Remise restaurant → coursier",
    desc: "Photographiez la commande, puis demandez au restaurant son code de remise à usage unique.",
    codeLabel: "Code du restaurant",
  },
  delivery: {
    title: "Remise coursier → client",
    desc: "Photographiez la remise, puis demandez au client son code de livraison à usage unique.",
    codeLabel: "Code du client",
  },
};

export function RepasCustodySheet({ missionId, phase, open, onOpenChange, onConfirmed }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [photoPath, setPhotoPath] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [attemptsLeft, setAttemptsLeft] = useState<number | null>(null);
  const [locked, setLocked] = useState(false);
  const copy = COPY[phase];

  const upload = async (f: File) => {
    setFile(f);
    setPhotoPath(null);
    setUploading(true);
    try {
      const ext = (f.name.split(".").pop() || "jpg").toLowerCase();
      const path = await uploadMissionProof(missionId, phase, f, ext);
      setPhotoPath(path);
      toast.success("Photo envoyée");
    } catch (e) {
      setPhotoPath(null);
      toast.error("Échec de l'envoi de la photo", {
        description: e instanceof Error ? e.message : undefined,
      });
    } finally {
      setUploading(false);
    }
  };

  const submit = async () => {
    if (!photoPath) {
      toast.error("Photo requise", { description: "Envoyez d'abord la photo de remise." });
      return;
    }
    if (locked) return;
    setBusy(true);
    try {
      const res =
        phase === "pickup"
          ? await confirmRepasHandoff(missionId, photoPath, code)
          : await confirmRepasDelivery(missionId, photoPath, code);
      if (isRefusal(res)) {
        setAttemptsLeft(res.attempts_left);
        setLocked(res.locked);
        setCode("");
        toast.error(refusalMessage(res));
        return;
      }
      toast.success(phase === "pickup" ? "Commande récupérée" : "Livraison confirmée");
      onConfirmed?.();
      onOpenChange(false);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl max-w-md mx-auto px-5 pb-8 pt-5">
        <SheetHeader className="text-left">
          <SheetTitle className="text-base font-bold">{copy.title}</SheetTitle>
          <SheetDescription className="text-xs">{copy.desc}</SheetDescription>
        </SheetHeader>

        <div className="mt-5 space-y-4">
          <label
            className={`flex items-center justify-center gap-2 h-24 rounded-2xl border-2 border-dashed cursor-pointer text-sm font-semibold ${
              photoPath
                ? "border-primary/50 bg-primary/5 text-primary"
                : "border-border text-muted-foreground hover:bg-muted"
            }`}
          >
            <input
              type="file"
              accept="image/*"
              capture="environment"
              className="sr-only"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) void upload(f);
              }}
            />
            {uploading ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" /> Envoi en cours…
              </>
            ) : photoPath ? (
              <>
                <Check className="w-4 h-4" /> Photo envoyée
              </>
            ) : (
              <>
                <Camera className="w-4 h-4" /> {file ? "Réessayer la photo" : "Prendre une photo"}
              </>
            )}
          </label>

          <div>
            <label className="text-xs font-semibold text-muted-foreground uppercase">
              {copy.codeLabel}
            </label>
            <Input
              inputMode="numeric"
              maxLength={6}
              value={code}
              disabled={locked}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              placeholder="000000"
              className="mt-1 h-12 text-center text-2xl tracking-[0.4em] font-bold tabular-nums"
            />
            {locked ? (
              <p className="mt-1.5 text-xs font-semibold text-destructive">
                Code bloqué après 5 tentatives. Contactez le support.
              </p>
            ) : attemptsLeft !== null ? (
              <p className="mt-1.5 text-xs font-semibold text-destructive">
                Code incorrect — {attemptsLeft} tentative{attemptsLeft > 1 ? "s" : ""} restante
                {attemptsLeft > 1 ? "s" : ""}.
              </p>
            ) : null}
          </div>

          <Button
            className="w-full h-12"
            onClick={submit}
            disabled={busy || uploading || locked || !photoPath || code.length !== 6}
          >
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Confirmer la remise"}
          </Button>

          <p className="inline-flex items-center gap-1 text-[10px] text-muted-foreground">
            <ShieldCheck className="w-3 h-3 text-primary" /> Remise vérifiée par CHOPCHOP — photo et
            code contrôlés côté serveur.
          </p>
        </div>
      </SheetContent>
    </Sheet>
  );
}
