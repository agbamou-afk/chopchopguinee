import { useState } from "react";
import { Loader2 } from "lucide-react";
import { QrScanner } from "@/components/scanner/QrScanner";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";

interface RidePickupScannerProps {
  rideId: string;
  onSuccess?: () => void;
  onCancel: () => void;
}

function normalizeDriverPickupCode(raw: string) {
  return raw.trim();
}

/** Ride-specific scanner: unlike the global BottomNav QR scanner, this calls
 * the pickup confirmation RPC for exactly one active ride. */
export function RidePickupScanner({ rideId, onSuccess, onCancel }: RidePickupScannerProps) {
  const [busy, setBusy] = useState(false);
  const [pendingCode, setPendingCode] = useState<string | null>(null);

  const confirmPickup = async (raw: string) => {
    const code = normalizeDriverPickupCode(raw);
    if (!code || busy) return;
    setPendingCode(code);
    setBusy(true);
    const { error } = await supabase.rpc("ride_confirm_pickup", {
      p_ride_id: rideId,
      p_code: code,
    });
    setBusy(false);
    setPendingCode(null);

    if (error) {
      toast({
        title: "Code chauffeur invalide",
        description: "Vérifiez que vous scannez le QR de votre chauffeur CHOPCHOP.",
      });
      return;
    }

    toast({
      title: "Pickup confirmé",
      description: "Course démarrée — bon voyage avec CHOPCHOP.",
    });
    onSuccess?.();
  };

  return (
    <>
      <QrScanner
        title="Scanner le code chauffeur"
        subtitle="QR du chauffeur pour cette course"
        expectedHint="Code chauffeur"
        onClose={onCancel}
        onResult={confirmPickup}
      />
      {busy && (
        <div className="fixed inset-x-4 bottom-24 z-[70] rounded-2xl border border-border bg-card/95 p-3 shadow-elevated backdrop-blur">
          <div className="flex items-center gap-3">
            <Loader2 className="h-5 w-5 animate-spin text-primary" />
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold">Confirmation du pickup…</p>
              <p className="truncate text-xs text-muted-foreground">Code scanné {pendingCode}</p>
            </div>
            <Button variant="ghost" size="sm" onClick={onCancel}>Fermer</Button>
          </div>
        </div>
      )}
    </>
  );
}