import { useEffect, useState } from "react";
import { Bug, RefreshCw, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useAuth } from "@/contexts/AuthContext";
import { useDriverSession } from "@/contexts/DriverSessionContext";

const tabLabel: Record<string, string> = {
  home: "Tableau",
  orders: "Courses",
  profile: "Profil",
};

function DebugRow({ label, value }: { label: string; value: string | number | boolean | null | undefined }) {
  return (
    <div className="flex items-start justify-between gap-2 text-[11px]">
      <span className="text-muted-foreground">{label}</span>
      <span className="max-w-[170px] break-all text-right font-mono text-foreground">
        {value === null || value === undefined || value === "" ? "—" : String(value)}
      </span>
    </div>
  );
}

export function DriverOfferDebugPanel({ activeTab }: { activeTab: string }) {
  const { user, isAdmin } = useAuth();
  const {
    profile,
    isOnline,
    queue,
    current,
    currentExpiresAt,
    latestOffer,
    realtimeStatus,
    activeRideId,
    activeTrip,
    blockingReason,
    refetchProfile,
    createDebugOfferForCurrentDriver,
  } = useDriverSession();
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const demoDebug = typeof window !== "undefined" && /[?&](demo|debug)=1/.test(window.location.search);
  const isDemoDriver = user?.email?.toLowerCase() === "demo.driver@chopchop.gn";
  if (!demoDebug && !isAdmin && !isDemoDriver) return null;

  const hasVisibleOffer = isOnline && queue.length > 0 && !activeTrip && !activeRideId;
  const bottomSheetShouldOpen = hasVisibleOffer && activeTab === "orders";
  const globalBannerShouldShow = hasVisibleOffer && activeTab !== "orders";
  const driverStatus = profile?.status === "suspended" ? "suspended" : profile?.presence ?? "offline";
  const expiresAt = currentExpiresAt ?? latestOffer?.expires_at ?? null;
  const remaining = expiresAt ? Math.max(0, Math.ceil((new Date(expiresAt).getTime() - now) / 1000)) : null;
  const exactBlocker = hasVisibleOffer
    ? activeTab === "orders"
      ? "visible_bottom_sheet"
      : "visible_global_banner"
    : blockingReason;

  const createOffer = async () => {
    setBusy(true);
    try {
      await createDebugOfferForCurrentDriver();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed left-3 right-3 top-20 z-[70] mx-auto max-w-md rounded-2xl border border-border bg-card/95 p-3 shadow-elevated backdrop-blur">
      <div className="mb-2 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-semibold text-foreground">
          <Bug className="h-4 w-4 text-primary" /> Driver Offer Debug
        </div>
        <Badge variant={hasVisibleOffer ? "default" : "secondary"}>{exactBlocker}</Badge>
      </div>
      <div className="grid grid-cols-1 gap-1.5">
        <DebugRow label="user_id" value={user?.id} />
        <DebugRow label="driver_profile_id" value={profile?.user_id} />
        <DebugRow label="is_demo_driver" value={isDemoDriver} />
        <DebugRow label="driver status" value={driverStatus} />
        <DebugRow label="active tab" value={tabLabel[activeTab] ?? activeTab} />
        <DebugRow label="realtime ride_offers" value={realtimeStatus} />
        <DebugRow label="pending offers" value={queue.length} />
        <DebugRow label="latest offer id" value={latestOffer?.id} />
        <DebugRow label="latest offer status" value={latestOffer?.status} />
        <DebugRow label="latest expires_at" value={latestOffer?.expires_at} />
        <DebugRow label="countdown" value={remaining == null ? null : `${remaining}s`} />
        <DebugRow label="bottom sheet open" value={bottomSheetShouldOpen} />
        <DebugRow label="global banner visible" value={globalBannerShouldShow} />
        <DebugRow label="active ride id" value={activeRideId} />
        <DebugRow label="blocking reason" value={exactBlocker} />
      </div>
      <div className="mt-3 flex gap-2">
        <Button size="sm" variant="outline" className="flex-1 gap-2" onClick={refetchProfile}>
          <RefreshCw className="h-4 w-4" /> Refresh
        </Button>
        <Button size="sm" className="flex-1 gap-2" disabled={busy || !user} onClick={createOffer}>
          <Send className="h-4 w-4" /> {busy ? "Création…" : "Créer une offre test pour ce chauffeur"}
        </Button>
      </div>
    </div>
  );
}