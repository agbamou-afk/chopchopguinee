import { useRef, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Camera, Loader2, QrCode, Check } from "lucide-react";
import { toast } from "sonner";
import { QrScanner } from "@/components/scanner/QrScanner";
import {
  uploadMissionProof,
  confirmPickupWithProof,
  confirmDropoffWithProof,
} from "@/lib/missions/proof";
import type { Mission } from "@/lib/missions/types";

interface Props {
  mission: Mission;
  kind: "pickup" | "delivery";
  open: boolean;
  onOpenChange: (o: boolean) => void;
  onDone?: () => void;
}

/**
 * Phase 5 — trust handshake for marketplace_delivery missions.
 * Courier must (1) attach a photo of the package, (2) provide the
 * 6-digit code held by the counterparty (merchant for pickup, buyer
 * for dropoff), and (3) submit to advance the mission state.
 */
export function MarketplaceTrustSheet({ mission, kind, open, onOpenChange, onDone }: Props) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [photo, setPhoto] = useState<File | null>(null);
  const [code, setCode] = useState("");
  const [scanning, setScanning] = useState(false);
  const [busy, setBusy] = useState(false);

  const reset = () => { setPhoto(null); setCode(""); setBusy(false); };

  const submit = async () => {
    if (!photo) { toast.error("Une photo est requise."); return; }
    if (!code.trim()) {
      toast.error(kind === "pickup" ? "Scannez le QR ou saisissez le code marchand." : "Saisissez le code client.");
      return;
    }
    setBusy(true);
    try {
      const path = await uploadMissionProof(mission.id, kind === "pickup" ? "pickup" : "delivery", photo);
      if (kind === "pickup") await confirmPickupWithProof(mission.id, path, code);
      else await confirmDropoffWithProof(mission.id, path, code);
      toast.success(kind === "pickup" ? "Retrait confirmé" : "Livraison confirmée");
      reset();
      onOpenChange(false);
      onDone?.();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <Sheet open={open} onOpenChange={(o) => { if (!busy) { if (!o) reset(); onOpenChange(o); } }}>
        <SheetContent side="bottom" className="rounded-t-3xl">
          <SheetHeader className="text-left">
            <SheetTitle>{kind === "pickup" ? "Confirmer le retrait" : "Confirmer la livraison"}</SheetTitle>
            <SheetDescription>
              {kind === "pickup"
                ? "Prenez une photo du colis et scannez le QR du marchand (ou saisissez son code)."
                : "Prenez une photo de la remise et saisissez le code à 6 chiffres du client."}
            </SheetDescription>
          </SheetHeader>

          <div className="space-y-3 mt-4">
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              capture="environment"
              className="hidden"
              onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
            />
            <Button
              type="button"
              variant="outline"
              className="w-full h-12 gap-2"
              onClick={() => fileRef.current?.click()}
              disabled={busy}
            >
              {photo ? <Check className="w-4 h-4 text-primary" /> : <Camera className="w-4 h-4" />}
              {photo ? `Photo prête (${Math.round(photo.size / 1024)} Ko)` : "Prendre la photo"}
            </Button>

            {kind === "pickup" && (
              <Button
                type="button"
                variant="outline"
                className="w-full h-12 gap-2"
                onClick={() => setScanning(true)}
                disabled={busy}
              >
                <QrCode className="w-4 h-4" /> Scanner le QR marchand
              </Button>
            )}

            <Input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder={kind === "pickup" ? "Code marchand (6 chiffres ou n° de compte)" : "Code client (6 chiffres)"}
              inputMode={kind === "delivery" ? "numeric" : "text"}
              maxLength={kind === "delivery" ? 6 : 32}
              disabled={busy}
              className="h-12 text-center text-lg tracking-widest"
            />

            <Button
              className="w-full h-12"
              onClick={submit}
              disabled={busy || !photo || !code.trim()}
            >
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Valider"}
            </Button>
          </div>
        </SheetContent>
      </Sheet>

      {scanning && (
        <QrScanner
          title="QR marchand"
          subtitle="Cadrez le QR du marchand"
          expectedHint="Code marchand"
          onClose={() => setScanning(false)}
          onResult={(text) => { setCode(text); setScanning(false); }}
        />
      )}
    </>
  );
}