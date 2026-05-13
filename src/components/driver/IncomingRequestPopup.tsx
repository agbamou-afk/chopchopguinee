import { motion, AnimatePresence } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { MapPin, Navigation, Clock, Star, X, Check, Bike } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useEffect, useState } from "react";

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

  useEffect(() => {
    if (!request) return;
    setRemaining(timeoutSec);
    const id = setInterval(() => {
      setRemaining((r) => {
        if (r <= 1) {
          clearInterval(id);
          onDecline(request.id);
          return 0;
        }
        return r - 1;
      });
    }, 1000);
    return () => clearInterval(id);
  }, [request, timeoutSec, onDecline]);

  return (
    <AnimatePresence>
      {request && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-[60] bg-foreground/40 backdrop-blur-sm flex items-end sm:items-center justify-center p-4"
        >
          <motion.div
            initial={{ y: 80, opacity: 0, scale: 0.95 }}
            animate={{ y: 0, opacity: 1, scale: 1 }}
            exit={{ y: 80, opacity: 0, scale: 0.95 }}
            transition={{ type: "spring", stiffness: 300, damping: 28 }}
            className="w-full max-w-md bg-card rounded-3xl shadow-elevated overflow-hidden"
          >
            {/* Countdown */}
            <div className="h-1.5 bg-muted">
              <motion.div
                key={request.id}
                initial={{ width: "100%" }}
                animate={{ width: "0%" }}
                transition={{ duration: timeoutSec, ease: "linear" }}
                className="h-full gradient-primary"
              />
            </div>

            <div className="p-5">
              <div className="flex items-center justify-between mb-3">
                <span className="px-3 py-1 rounded-full bg-primary/10 text-primary text-xs font-semibold">
                  Nouvelle {TYPE_LABEL[request.type]}
                </span>
                <div className="flex items-center gap-1 text-xs text-muted-foreground">
                  <Clock className="w-3.5 h-3.5" />
                  <span className="font-medium">{remaining}s</span>
                </div>
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

              <div className="flex gap-3">
                <Button
                  variant="outline"
                  onClick={() => onDecline(request.id)}
                  className="flex-1 h-12 border-destructive text-destructive hover:bg-destructive hover:text-destructive-foreground"
                >
                  <X className="w-5 h-5 mr-1" /> Refuser
                </Button>
                <Button
                  onClick={() => onAccept(request.id)}
                  className="flex-1 h-12 gradient-primary"
                >
                  <Check className="w-5 h-5 mr-1" /> Accepter
                </Button>
              </div>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
