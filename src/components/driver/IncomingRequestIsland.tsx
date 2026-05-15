import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MapPin, Navigation, Clock, X, Check } from "lucide-react";
import { formatGNF } from "@/lib/format";
import type { IncomingRequest } from "./IncomingRequestPopup";

function vibrate(pattern: number | number[]) {
  try {
    if (typeof navigator !== "undefined" && "vibrate" in navigator) {
      (navigator as Navigator).vibrate(pattern);
    }
  } catch {
    /* noop */
  }
}

interface Props {
  request: IncomingRequest | null;
  onAccept: (id: string) => void;
  onDecline: (id: string) => void;
  timeoutSec?: number;
}

/**
 * Floating "island" variant of the ride-offer popup. Compact, glassy,
 * centred above the BottomNav. Used in the driver Courses tab where the
 * map is full-bleed.
 */
export function IncomingRequestIsland({
  request,
  onAccept,
  onDecline,
  timeoutSec = 20,
}: Props) {
  const [remaining, setRemaining] = useState(timeoutSec);
  const vibratedRef = useRef<string | null>(null);

  useEffect(() => {
    if (!request) return;
    setRemaining(timeoutSec);
    if (vibratedRef.current !== request.id) {
      vibratedRef.current = request.id;
      vibrate([300, 100, 300, 100, 500]);
    }
    const id = setInterval(() => {
      setRemaining((r) => {
        if (r <= 1) {
          clearInterval(id);
          onDecline(request.id);
          return 0;
        }
        if (r - 1 <= 5) vibrate(180);
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
          initial={{ opacity: 0, y: 24, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 24, scale: 0.96 }}
          transition={{ type: "spring", stiffness: 320, damping: 28 }}
          className="fixed left-1/2 -translate-x-1/2 z-[60] px-3 w-full max-w-[22rem] pointer-events-none"
          style={{ bottom: "calc(5.25rem + env(safe-area-inset-bottom))" }}
          role="dialog"
          aria-label="Nouvelle demande de course"
        >
          <div className="pointer-events-auto rounded-3xl bg-card/85 backdrop-blur-xl border border-border/60 shadow-elevated overflow-hidden">
            {/* Countdown */}
            <div className="h-1 bg-muted/60">
              <motion.div
                key={request.id}
                initial={{ width: "100%" }}
                animate={{ width: "0%" }}
                transition={{ duration: timeoutSec, ease: "linear" }}
                className={`h-full ${urgent ? "bg-destructive" : "gradient-primary"}`}
              />
            </div>

            <div className="p-3.5 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-bold uppercase tracking-wide text-primary">
                  Nouvelle course
                </span>
                <motion.div
                  key={remaining}
                  initial={{ scale: 1.15, opacity: 0.7 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ duration: 0.2 }}
                  className={`flex items-center gap-1 px-2 py-0.5 rounded-full font-bold tabular-nums text-[11px] ${
                    urgent
                      ? "bg-destructive/15 text-destructive"
                      : "bg-muted text-foreground"
                  }`}
                >
                  <Clock className="w-3 h-3" />
                  {remaining}s
                </motion.div>
              </div>

              <div className="space-y-1.5">
                <div className="flex items-center gap-2 min-w-0">
                  <MapPin className="w-3.5 h-3.5 text-primary shrink-0" />
                  <p className="text-sm font-semibold text-foreground truncate">
                    {request.pickup}
                  </p>
                </div>
                <div className="flex items-center gap-2 min-w-0">
                  <Navigation className="w-3.5 h-3.5 text-secondary shrink-0" />
                  <p className="text-sm font-medium text-muted-foreground truncate">
                    {request.destination}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
                <span className="font-semibold text-foreground">
                  {formatGNF(request.estimatedPrice)}
                </span>
                <span>·</span>
                <span>{request.distance}</span>
                <span>·</span>
                <span>{request.eta}</span>
              </div>

              <div className="flex gap-2 pt-1">
                <button
                  onClick={() => onDecline(request.id)}
                  className="h-11 px-3 rounded-2xl border border-destructive/40 text-destructive font-semibold text-sm bg-background/50 hover:bg-destructive/5 active:scale-95 transition inline-flex items-center justify-center gap-1"
                  aria-label="Refuser"
                >
                  <X className="w-4 h-4" />
                  Refuser
                </button>
                <motion.button
                  onClick={() => onAccept(request.id)}
                  animate={{ scale: [1, 1.03, 1] }}
                  transition={{ duration: 1.4, repeat: Infinity, ease: "easeInOut" }}
                  className="flex-1 h-11 rounded-2xl gradient-primary text-primary-foreground font-bold text-sm shadow-card ring-2 ring-primary/40 inline-flex items-center justify-center gap-1.5"
                  aria-label="Accepter"
                >
                  <Check className="w-5 h-5" />
                  Accepter
                </motion.button>
              </div>
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}