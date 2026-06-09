import { useState } from "react";
import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScanLine, KeyRound, Loader2, ShieldCheck, CheckCircle2, Phone, Bike } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { RidePickupScanner } from "./RidePickupScanner";
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
  vehicleLabel?: string;
  plate?: string | null;
  onCallDriver?: () => void;
}

/**
 * Pickup confirmation handshake. Shown to the client when ride.status === 'pending'
 * and metadata.phase === 'arrived'. Calls ride_confirm_pickup which transitions
 * the ride to in_progress on success.
 */
export function PickupConfirmCard({
  rideId,
  driverName,
  pickupCode,
  vehicleLabel,
  plate,
  onCallDriver,
}: Props) {
  const [scanning, setScanning] = useState(false);
  const [manualOpen, setManualOpen] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const { user } = useAuth();
  const mode = getRuntimeMode(user);
  // No demo runtime mode any more — keep the strict pickup handshake by default.
  const isDemo = false;
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
      description: "Course démarrée — bon voyage avec CHOPCHOP.",
    });
  };

  return (
    <>
      {scanning && (
        <RidePickupScanner
          rideId={rideId}
          onCancel={() => setScanning(false)}
          onSuccess={() => {
            setScanning(false);
            setManualOpen(false);
            setCode("");
          }}
        />
      )}
      <motion.div
        initial={{ y: 20, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="absolute left-3 right-3 bottom-3 z-20 rounded-2xl border-2 border-primary bg-card/95 backdrop-blur-md p-4 shadow-elevated space-y-3 ring-4 ring-primary/15"
      >
        <div>
          <p className="text-[10px] uppercase tracking-wide text-primary font-semibold flex items-center gap-1.5">
            <span className="relative inline-flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary/60" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-primary" />
            </span>
            Votre chauffeur est arrivé
          </p>
          <p className="text-lg font-bold leading-tight mt-0.5">
            Votre chauffeur est arrivé
          </p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Scannez le code affiché sur l'application du chauffeur pour démarrer officiellement la course.
          </p>
          <TrustCues
            cues={["verified", "choppay"]}
            className="mt-2"
            compact
          />
        </div>

        {(driverName || vehicleLabel || plate) && (
          <div className="flex items-center gap-3 rounded-xl bg-muted/40 p-2.5">
            <div className="h-9 w-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
              <Bike className="h-4 w-4 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold truncate">{driverName ?? "Votre chauffeur"}</p>
              <p className="text-[11px] text-muted-foreground truncate">
                {[vehicleLabel, plate].filter(Boolean).join(" · ") || "En attente d'infos véhicule"}
              </p>
            </div>
            {onCallDriver && (
              <Button
                size="icon"
                variant="outline"
                className="h-9 w-9 rounded-full"
                onClick={onCallDriver}
                aria-label="Appeler le chauffeur"
              >
                <Phone className="h-4 w-4" />
              </Button>
            )}
          </div>
        )}

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
            className={`w-full h-14 text-base font-bold ${isDemo ? "" : "gradient-primary"}`}
            variant={isDemo ? "outline" : "default"}
          >
            <ScanLine className="w-5 h-5 mr-2" /> Scanner le code chauffeur
          </Button>
          <Button
            variant="outline"
            onClick={() => setManualOpen((v) => !v)}
            disabled={busy}
            className="w-full h-10"
          >
            <KeyRound className="w-4 h-4 mr-2" /> Entrer le code chauffeur
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
              placeholder="Code chauffeur (ex: ABC123)"
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