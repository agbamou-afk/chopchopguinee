import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { BellRing, ChevronRight, MapPin } from "lucide-react";
import { formatGNF } from "@/lib/format";
import { useDriverSession } from "@/contexts/DriverSessionContext";

interface Props {
  /** Current driver tab — banner hides on the Courses tab. */
  activeTab: string;
  /** Switch to the Courses tab and surface the bottom sheet. */
  onView: () => void;
}

/**
 * Compact persistent ride-offer alert shown on Tableau / Profil tabs.
 * The full accept/decline bottom sheet lives in the Courses tab — this
 * banner just nudges the driver to switch and act.
 */
export function DriverRideAlertBanner({ activeTab, onView }: Props) {
  const { isOnline, current, currentExpiresAt, queue } = useDriverSession();
  const [now, setNow] = useState(Date.now());
  const displayedRequest = current ?? queue[0] ?? null;

  // Tick once per second for the countdown.
  useEffect(() => {
    if (!displayedRequest) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [displayedRequest?.id]);

  // Hide on Courses tab — the full bottom sheet handles it there.
  if (activeTab === "orders") return null;
  if (!isOnline) return null;
  if (!displayedRequest) return null;

  const remainingSec = currentExpiresAt
    ? Math.max(0, Math.ceil((new Date(currentExpiresAt).getTime() - now) / 1000))
    : null;
  const extra = queue.length > 1 ? ` • +${queue.length - 1}` : "";

  return (
    <AnimatePresence>
      <motion.button
        key={displayedRequest.id}
        initial={{ y: -80, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: -80, opacity: 0 }}
        transition={{ type: "spring", stiffness: 320, damping: 28 }}
        onClick={onView}
        className="fixed top-3 left-3 right-3 z-40 flex items-center gap-3 p-3 rounded-2xl
          bg-card border border-primary/40 shadow-elevated text-left
          hover:bg-primary/5 transition"
        aria-label="Voir la nouvelle demande de course"
      >
        <div className="relative shrink-0">
          <div className="p-2 rounded-xl bg-primary/15">
            <BellRing className="w-5 h-5 text-primary" />
          </div>
          <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-primary animate-pulse" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground leading-tight">
            Nouvelle course disponible{extra}
          </p>
          <p className="text-[11px] text-muted-foreground truncate flex items-center gap-1">
            <MapPin className="w-3 h-3 shrink-0" />
            <span className="truncate">{displayedRequest.pickup}</span>
            <span className="mx-1">·</span>
            <span className="font-medium text-foreground">{formatGNF(displayedRequest.estimatedPrice)}</span>
          </p>
        </div>
        <div className="flex flex-col items-end shrink-0">
          {remainingSec != null && (
            <span className="text-[11px] tabular-nums font-semibold text-primary">
              {remainingSec}s
            </span>
          )}
          <span className="text-[11px] font-semibold text-foreground inline-flex items-center gap-0.5">
            Voir <ChevronRight className="w-3 h-3" />
          </span>
        </div>
      </motion.button>
    </AnimatePresence>
  );
}