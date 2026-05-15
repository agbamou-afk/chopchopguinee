import { useState } from "react";
import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScanLine, KeyRound, Loader2, ShieldCheck, CheckCircle2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { QrScanner } from "@/components/scanner/QrScanner";
import { getRuntimeMode } from "@/lib/runtimeMode";
import { useAuth } from "@/contexts/AuthContext";
import { TrustCues } from "@/components/trust/TrustCues";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { useEffect } from "react";

interface Props {
  rideId: string;
  driverName?: string | null;
  /** The actual pickup code on the ride; used for the demo bypass shortcut. */
  pickupCode?: string | null;
}

/**
 * Pickup confirmation handshake. Shown to the client when ride.status === 'pending'
 * and metadata.phase === 'arrived'. Calls ride_confirm_pickup which transitions
 * the ride to in_progress on success.
 */
export function PickupConfirmCard({ rideId, driverName, pickupCode }: Props) {
  const [scanning, setScanning] = useState(false);
  const [manualOpen, setManualOpen] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const { user } = useAuth();
  const mode = getRuntimeMode(user?.email);
  const isDemo = mode === "demo";
  const isSandbox = mode === "sandbox";

  useEffect(() => {
    try {
      Analytics.track("ride.trust_message_viewed" as any, {
        metadata: { surface: "pickup_confirm" },
      });
    } catch {}
  }, []);

  const submit = async (raw: string) => {
    const value = raw.trim();
    if (!value) return;
    setBusy(true);
    const { error } = await supabase.rpc("ride_confirm_pickup", {
      p_ride_id: rideId,
      p_code: value,
    });
    setBusy(false);
    if (error) {
      toast({ title: "Code invalide", description: error.message });
      return;
    }
    setScanning(false);
    setManualOpen(false);
    setCode("");
    toast({
      title: "Pickup confirmé",
      description: "Course démarrée — bon voyage avec CHOP CHOP.",
    });
  };

  return (
    <>
      {scanning && (
        <QrScanner
          title="Confirmer la prise en charge"
          subtitle="Scannez le QR affiché par le chauffeur"
          onClose={() => setScanning(false)}
          onResult={(t) => submit(t)}
        />
      )}
      <motion.div
        initial={{ y: 20, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="absolute left-3 right-3 bottom-3 z-20 rounded-2xl border border-border bg-card/95 backdrop-blur-md p-4 shadow-elevated space-y-3"
      >
        <div>
          <p className="text-[10px] uppercase tracking-wide text-primary font-semibold">
            Chauffeur arrivé · prêt à partir
          </p>
          <p className="text-base font-semibold">
            {driverName ? `${driverName} vous attend` : "Votre chauffeur vous attend"}
          </p>
          <p className="text-xs text-muted-foreground">
            Confirmez la prise en charge pour sécuriser le départ.
          </p>
          <TrustCues
            cues={["verified", "choppay"]}
            className="mt-2"
            compact
          />
        </div>

        {isDemo && pickupCode && (
          <Button
            onClick={() => submit(pickupCode)}
            disabled={busy}
            className="w-full h-12 gradient-primary text-base font-semibold"
          >
            {busy ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <CheckCircle2 className="w-5 h-5 mr-2" />}
            Confirmer pickup démo
          </Button>
        )}

        <div className="grid grid-cols-1 gap-2">
          <Button
            onClick={() => setScanning(true)}
            disabled={busy}
            className={`w-full h-11 ${isDemo ? "" : "gradient-primary"}`}
            variant={isDemo ? "outline" : "default"}
          >
            <ScanLine className="w-4 h-4 mr-2" /> Scanner le QR du chauffeur
          </Button>
          <Button
            variant="outline"
            onClick={() => setManualOpen((v) => !v)}
            disabled={busy}
            className="w-full h-10"
          >
            <KeyRound className="w-4 h-4 mr-2" /> Saisir le code manuellement
          </Button>
        </div>

        {manualOpen && (
          <form
            onSubmit={(e) => { e.preventDefault(); submit(code); }}
            className="flex gap-2"
          >
            <Input
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              placeholder="ABC123"
              maxLength={20}
              autoFocus
              className="tracking-[0.25em] font-mono text-center"
            />
            <Button type="submit" disabled={busy || code.length < 4}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Valider"}
            </Button>
          </form>
        )}

        {isSandbox && pickupCode && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => submit(pickupCode)}
            disabled={busy}
            className="w-full text-muted-foreground hover:text-foreground gap-1.5"
          >
            <ShieldCheck className="h-3.5 w-3.5" /> Sandbox: force pickup ({pickupCode})
          </Button>
        )}
      </motion.div>
    </>
  );
}