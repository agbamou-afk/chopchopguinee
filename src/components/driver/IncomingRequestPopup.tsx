import { motion, AnimatePresence } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { MapPin, Navigation, Clock, Star, X, Check, Bike } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useEffect, useRef, useState } from "react";

// --- Placeholders: replace with real implementations later ---
function useRequestSound(active: boolean) {
  // Placeholder for ride-offer alert sound. Wire to <audio> or Web Audio API later.
  useEffect(() => {
    if (!active) return;
    // e.g. const a = new Audio("/sounds/incoming.mp3"); a.loop = true; a.play().catch(()=>{});
    // return () => { a.pause(); };
  }, [active]);
}

function triggerVibration(pattern: number | number[]) {
  // Placeholder for haptic feedback. Native bridge can override later.
  try {
    if (typeof navigator !== "undefined" && "vibrate" in navigator) {
      (navigator as Navigator).vibrate(pattern);
    }
  } catch {
    /* noop */
  }
}

export interface IncomingRequest {
  id: string;
  type: "ride" | "delivery" | "food";
  pickup: string;
  destination: string;
  customerName: string;
  customerRating: number;
  estimatedPrice: number;
  distance: string;
  eta: string;
}

interface Props {
  request: IncomingRequest | null;
  onAccept: (id: string) => void;
  onDecline: (id: string) => void;
  timeoutSec?: number;
}

const TYPE_LABEL = { ride: "Course Moto", delivery: "Livraison", food: "Repas" } as const;

export function IncomingRequestPopup({ request, onAccept, onDecline, timeoutSec = 20 }: Props) {
  const [remaining, setRemaining] = useState(timeoutSec);
  const vibratedRef = useRef<string | null>(null);

  useRequestSound(!!request);

  useEffect(() => {
    if (!request) return;
    setRemaining(timeoutSec);
    // Vibrate once per incoming request (urgent attention pattern).
    if (vibratedRef.current !== request.id) {
      vibratedRef.current = request.id;
      triggerVibration([400, 120, 400, 120, 600]);
    }
    const id = setInterval(() => {
      setRemaining((r) => {
        if (r <= 1) {
          clearInterval(id);
          onDecline(request.id);
          return 0;
        }
        // Re-pulse haptics in the final 5 seconds.
        if (r - 1 <= 5) triggerVibration(200);
        return r - 1;
      });
    }, 1000);
    return () => clearInterval(id);
  }, [request, timeoutSec, onDecline]);

  const urgent = remaining <= 5;

  return (
    <AnimatePresence>
      {request && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-x-0 bottom-0 z-[60] pointer-events-none"
          aria-live="polite"
        >
          <motion.div
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", stiffness: 320, damping: 32 }}
            className="pointer-events-auto mx-auto w-full max-w-md bg-card rounded-t-3xl shadow-elevated overflow-hidden border-t border-border/60 pb-[max(0.75rem,env(safe-area-inset-bottom))]"
            role="dialog"
            aria-label="Nouvelle demande de course"
          >
            {/* Drag handle */}
            <div className="flex justify-center pt-2 pb-1">
              <div className="w-10 h-1.5 rounded-full bg-muted-foreground/25" />
            </div>
            {/* Countdown */}
            <div className="h-2 bg-muted">
              <motion.div
                key={request.id}
                initial={{ width: "100%" }}
                animate={{ width: "0%" }}
                transition={{ duration: timeoutSec, ease: "linear" }}
                className={`h-full ${urgent ? "bg-destructive" : "gradient-primary"}`}
              />
            </div>

            <div className="p-5">
              <div className="flex items-center justify-between mb-3">
                <span className="px-3 py-1 rounded-full bg-primary/10 text-primary text-xs font-semibold">
                  Nouvelle {TYPE_LABEL[request.type]}
                </span>
                <motion.div
                  key={remaining}
                  initial={{ scale: urgent ? 1.25 : 1.05, opacity: 0.6 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ duration: 0.25 }}
                  className={`flex items-center gap-1 px-2.5 py-1 rounded-full font-bold tabular-nums ${
                    urgent
                      ? "bg-destructive/15 text-destructive text-sm"
                      : "bg-muted text-foreground text-xs"
                  }`}
                >
                  <Clock className={urgent ? "w-4 h-4" : "w-3.5 h-3.5"} />
                  <span>{remaining}s</span>
                </motion.div>
              </div>

              {/* Mini route preview */}
              <div className="relative bg-muted/60 rounded-2xl p-4 mb-4">
                <svg viewBox="0 0 300 70" className="w-full h-12 mb-3">
                  <path
                    d="M10 55 Q 80 10, 150 35 T 290 15"
                    stroke="hsl(var(--primary))"
                    strokeWidth="3"
                    fill="none"
                    strokeDasharray="6 5"
                  />
                  <circle cx="10" cy="55" r="6" fill="hsl(var(--primary))" />
                  <circle cx="290" cy="15" r="6" fill="hsl(var(--secondary))" />
                </svg>
                <div className="space-y-2">
                  <div className="flex items-start gap-2">
                    <MapPin className="w-4 h-4 mt-0.5 text-primary shrink-0" />
                    <div className="min-w-0">
                      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Départ</p>
                      <p className="text-sm font-medium text-foreground truncate">{request.pickup}</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-2">
                    <Navigation className="w-4 h-4 mt-0.5 text-secondary shrink-0" />
                    <div className="min-w-0">
                      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Destination</p>
                      <p className="text-sm font-medium text-foreground truncate">{request.destination}</p>
                    </div>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-2 mb-4 text-center">
                <div className="bg-muted/50 rounded-xl py-2">
                  <p className="text-[10px] text-muted-foreground uppercase">Distance</p>
                  <p className="text-sm font-bold text-foreground">{request.distance}</p>
                </div>
                <div className="bg-muted/50 rounded-xl py-2">
                  <p className="text-[10px] text-muted-foreground uppercase">Durée</p>
                  <p className="text-sm font-bold text-foreground">{request.eta}</p>
                </div>
                <div className="bg-primary/10 rounded-xl py-2">
                  <p className="text-[10px] text-primary uppercase">Gain</p>
                  <p className="text-sm font-bold text-primary">
                    {formatGNF(request.estimatedPrice)}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2 mb-4 text-sm">
                <div className="w-9 h-9 rounded-full bg-muted flex items-center justify-center text-foreground font-semibold">
                  {request.customerName.charAt(0)}
                </div>
                <span className="text-foreground font-medium">{request.customerName}</span>
                <div className="flex items-center gap-1 ml-auto">
                  <Star className="w-3.5 h-3.5 fill-secondary text-secondary" />
                  <span className="text-foreground font-medium">{request.customerRating}</span>
                </div>
              </div>

              <div className="flex gap-3 items-stretch">
                <Button
                  variant="outline"
                  onClick={() => onDecline(request.id)}
                  className="w-24 h-14 border-destructive text-destructive hover:bg-destructive hover:text-destructive-foreground"
                >
                  <X className="w-5 h-5 mr-1" /> Refuser
                </Button>
                <motion.div
                  className="flex-1"
                  animate={{ scale: [1, 1.03, 1] }}
                  transition={{ duration: 1.4, repeat: Infinity, ease: "easeInOut" }}
                >
                  <Button
                    onClick={() => onAccept(request.id)}
                    className="w-full h-14 gradient-primary text-base font-bold shadow-elevated ring-2 ring-primary/40 ring-offset-2 ring-offset-card"
                  >
                    <Check className="w-6 h-6 mr-2" /> Accepter
                  </Button>
                </motion.div>
              </div>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
