import { memo, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MapPin, Navigation, Clock, X, Check, ShieldCheck } from "lucide-react";
import { formatGNF } from "@/lib/format";
import type { IncomingRequest } from "./IncomingRequestPopup";
import {
  playOfferIncoming,
  playOfferAccepted,
  unlockDriverSounds,
} from "@/lib/sound/driverSounds";
import { useLowDataMode } from "@/hooks/useLowDataMode";
import { Analytics } from "@/lib/analytics/AnalyticsService";

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
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const [interacted, setInteracted] = useState(false);
  const vibratedRef = useRef<string | null>(null);
  const soundedRef = useRef<string | null>(null);
  const { low } = useLowDataMode();

  useEffect(() => {
    if (!request) return;
    setRemaining(timeoutSec);
    setInteracted(false);
    try {
      Analytics.track("driver.trust_message_viewed" as any, {
        metadata: { surface: "incoming_request", rideId: request.id },
      });
    } catch {}
    if (vibratedRef.current !== request.id) {
      vibratedRef.current = request.id;
      vibrate([300, 100, 300, 100, 500]);
    }
    if (soundedRef.current !== request.id) {
      soundedRef.current = request.id;
      playOfferIncoming();
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
        <>
          {/* Soft focus wash — no backdrop-filter, opacity-only, disabled in low-data mode */}
          {!low && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.3, ease: "easeOut" }}
              className="fixed inset-0 z-[55] pointer-events-none"
              style={{
                background:
                  "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 0%, rgba(0,0,0,0.06) 55%, rgba(0,0,0,0.10) 100%)",
              }}
              aria-hidden
            />
          )}
          <div
            className="fixed inset-0 z-[60] flex items-center justify-center pointer-events-none px-3"
            aria-hidden={false}
          >
          <motion.div
            key={request.id}
            initial={{ opacity: 0, scale: 0.96, y: 6 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 6 }}
            transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
            role="dialog"
            aria-label="Nouvelle demande de course"
            onPointerDownCapture={() => setInteracted(true)}
            className={`w-[min(348px,100%)] will-change-transform pointer-events-auto rounded-2xl bg-card/97 backdrop-blur-md overflow-hidden shadow-island border ${
              urgent ? "border-destructive/50 ring-2 ring-destructive/25" : "border-primary/15"
            } transition-colors duration-200`}
          >
            {/* Brand seam — saffron→ember directional flow */}
            <div className="pointer-events-none h-[2px] bg-gradient-to-r from-primary/70 via-secondary to-primary/70" aria-hidden />
            {/* Countdown */}
            <CountdownBar id={request.id} duration={timeoutSec} urgent={urgent} />

            <div className="p-4 space-y-3.5">
              <div className="flex items-center justify-between">
                <span className="inline-flex items-center gap-2 text-[10.5px] font-bold uppercase tracking-[0.18em] text-primary">
                  <span className="relative flex h-2 w-2">
                    <span className="absolute inline-flex h-full w-full rounded-full bg-primary/60 animate-ping" />
                  <span className="relative inline-flex h-2 w-2 rounded-full bg-primary" />
                  </span>
                  Nouvelle course · client vérifié
                </span>
                <div
                  className={`flex items-center gap-1 px-2 py-1 rounded-full font-semibold tabular-nums text-[11px] ${
                    urgent
                      ? "bg-destructive/15 text-destructive"
                      : "bg-muted text-muted-foreground"
                  }`}
                >
                  <Clock className="w-3 h-3" />
                  {remaining}s
                </div>
              </div>

              <div className="space-y-2 rounded-2xl bg-muted/40 p-3 border border-border/50">
                <div className="flex items-center gap-2.5 min-w-0">
                  <span className="w-6 h-6 shrink-0 rounded-lg bg-primary/12 flex items-center justify-center">
                    <MapPin className="w-3.5 h-3.5 text-primary" />
                  </span>
                  <p className="text-sm font-semibold text-foreground truncate">
                    {request.pickup}
                  </p>
                </div>
                <div className="flex items-center gap-2.5 min-w-0">
                  <span className="w-6 h-6 shrink-0 rounded-lg bg-secondary/20 flex items-center justify-center">
                    <Navigation className="w-3.5 h-3.5 text-secondary-foreground" />
                  </span>
                  <p className="text-sm font-medium text-foreground/85 truncate">
                    {request.destination}
                  </p>
                </div>
              </div>

              <div className="flex items-center justify-between text-[11px] text-muted-foreground px-1">
                <span className="font-bold text-foreground tabular-nums text-sm">
                  {formatGNF(request.estimatedPrice)}
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span>{request.distance}</span>
                  <span className="opacity-50">·</span>
                  <span>{request.eta}</span>
                </span>
              </div>

              <div className="flex items-center gap-1.5 text-[10.5px] text-muted-foreground px-1">
                <ShieldCheck className="w-3 h-3 text-success" aria-hidden />
                Gain crédité automatiquement à votre CHOPWallet
              </div>

              <div className="flex gap-2 pt-0.5">
                <button
                  onClick={() => {
                    setInteracted(true);
                    unlockDriverSounds();
                    onDecline(request.id);
                  }}
                  className="h-12 px-4 rounded-2xl border border-border text-muted-foreground font-medium text-sm bg-background/40 hover:bg-muted/60 active:scale-[0.97] transition inline-flex items-center justify-center gap-1"
                  aria-label="Refuser"
                >
                  <X className="w-4 h-4" />
                  Refuser
                </button>
                <button
                  onClick={() => {
                    setInteracted(true);
                    unlockDriverSounds();
                    playOfferAccepted();
                    onAccept(request.id);
                  }}
                  className="flex-1 h-12 rounded-2xl gradient-cta text-primary-foreground font-bold text-sm inline-flex items-center justify-center gap-1.5 active:scale-[0.985] transition-transform"
                  aria-label="Accepter"
                >
                  <Check className="w-5 h-5" />
                  Accepter
                </button>
              </div>
            </div>
          </motion.div>
          </div>
        </>
      )}
    </AnimatePresence>
  );
}

const CountdownBar = memo(function CountdownBar({
  id,
  duration,
  urgent,
}: {
  id: string;
  duration: number;
  urgent: boolean;
}) {
  return (
    <div className="h-1 bg-muted/60">
      <motion.div
        key={id}
        initial={{ width: "100%" }}
        animate={{ width: "0%" }}
        transition={{ duration, ease: "linear" }}
        className={`h-full ${urgent ? "bg-destructive" : "gradient-primary"}`}
      />
    </div>
  );
});