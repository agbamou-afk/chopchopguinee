import { motion } from "framer-motion";
import { Power, BellRing, Radar, Users, Star, TrendingUp, Timer, AlertTriangle, Clock, ShieldCheck, FileWarning } from "lucide-react";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { DriverDashboard } from "@/components/driver/DriverDashboard";
import { IncomingRequestPopup, type IncomingRequest } from "@/components/driver/IncomingRequestPopup";
import { DriverTripView } from "@/components/driver/DriverTripView";
import { DriverActiveTrip } from "@/components/driver/DriverActiveTrip";
import { AppHeader } from "@/components/ui/AppHeader";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { LiveRidesPanel } from "@/components/driver/LiveRidesPanel";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { useWallet } from "@/hooks/useWallet";
import { useDriverProfile } from "@/hooks/useDriverProfile";
import { useDriverPresence } from "@/hooks/useDriverPresence";
import { useIncomingOffers, type RideOffer } from "@/hooks/useIncomingOffers";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { formatGNF } from "@/lib/format";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface DriverHomeProps {
  onToggleDriverMode: () => void;
}

function offerToRequest(o: RideOffer): IncomingRequest {
  const distKm = o.distance_to_pickup_m ? (o.distance_to_pickup_m / 1000).toFixed(1) : "—";
  return {
    id: o.id,
    type: "ride",
    pickup: o.pickup_zone || "Point de départ",
    destination: o.destination_zone || "Destination",
    customerName: "Client",
    customerRating: 5,
    estimatedPrice: o.estimated_earning_gnf ?? o.estimated_fare_gnf ?? 0,
    distance: distKm === "—" ? "—" : `${distKm} km`,
    eta: "—",
  };
}

export function DriverHome({ onToggleDriverMode }: DriverHomeProps) {
  const navigate = useNavigate();
  const { profile, loading: profileLoading, refetch } = useDriverProfile();
  const [isOnline, setIsOnline] = useState(false);
  const [toggling, setToggling] = useState(false);
  const [current, setCurrent] = useState<IncomingRequest | null>(null);
  const [activeTrip, setActiveTrip] = useState<IncomingRequest | null>(null);
  const [activeRideId, setActiveRideId] = useState<string | null>(null);
  const { available: driverBalance, loading: walletLoading } = useWallet("driver");
  const { offers, refetch: refetchOffers } = useIncomingOffers(isOnline);
  const queue = offers.map(offerToRequest);

  useDriverPresence({ enabled: isOnline, onTrip: !!activeTrip });

  // Sync local toggle with persisted presence
  useEffect(() => {
    if (profile) setIsOnline(profile.presence !== "offline");
  }, [profile?.presence]);

  const cashOverLimit = !!profile && profile.cash_debt_gnf >= profile.debt_limit_gnf;

  const handleTogglePresence = async () => {
    if (!profile || toggling) return;
    const next = isOnline ? "offline" : "online";
    if (next === "online" && cashOverLimit) {
      toast.error("Limite de cash atteinte. Réglez votre commission pour repasser en ligne.");
      Analytics.track("driver.cash.over_limit", { metadata: { cash_debt_gnf: profile.cash_debt_gnf } });
      return;
    }
    setToggling(true);
    const { error } = await supabase.rpc("driver_set_status", { p_status: next });
    setToggling(false);
    if (error) {
      toast.error(error.message || "Impossible de changer le statut.");
      return;
    }
    setIsOnline(next === "online");
    refetch();
    Analytics.track(next === "online" ? "driver.online" : "driver.offline", {
      metadata: { vehicle_type: profile.vehicle_type },
    });
    toast.success(next === "online" ? "Vous êtes en ligne." : "Vous êtes hors ligne.");
  };

  // Auto-pop next offer when online and idle
  useEffect(() => {
    if (!isOnline || current || activeTrip || queue.length === 0) return;
    setCurrent(queue[0]);
  }, [isOnline, current, activeTrip, queue]);

  const handleAccept = async (id: string) => {
    const accepted = current;
    setCurrent(null);
    const { data, error } = await supabase.rpc("driver_offer_accept", { p_offer_id: id });
    if (error) {
      toast.error(error.message || "Impossible d'accepter cette course.");
      refetchOffers();
      return;
    }
    if (accepted) {
      setActiveTrip(accepted);
      const rideId = (data as any)?.ride_id as string | undefined;
      if (rideId) setActiveRideId(rideId);
      toast.success("Course acceptée — direction le client.");
    }
    Analytics.track("driver.ride.accepted", { metadata: { offer_id: id, fare_gnf: accepted?.estimatedPrice } });
    refetchOffers();
  };

  const handleDecline = async (id: string) => {
    setCurrent(null);
    const { error } = await supabase.rpc("driver_offer_decline", { p_offer_id: id });
    if (error) toast.error(error.message);
    else toast.info("Course refusée");
    Analytics.track("driver.ride.declined", { metadata: { offer_id: id } });
    refetchOffers();
  };

  const triggerNext = () => {
    if (queue.length === 0) {
      toast.info("Aucune demande en attente");
      return;
    }
    setCurrent(queue[0]);
  };

  // Application/status gating UI
  if (!profileLoading && (!profile || profile.status !== "approved")) {
    const status = profile?.status;
    const config = !profile
      ? {
          icon: ShieldCheck,
          tone: "text-primary",
          title: "Devenez chauffeur CHOP CHOP",
          desc: "Soumettez votre dossier pour commencer à recevoir des courses.",
          cta: "Commencer ma demande",
          to: "/driver/apply",
        }
      : status === "pending"
        ? {
            icon: Clock,
            tone: "text-amber-600",
            title: "Demande en cours d'examen",
            desc: "Notre équipe vérifie vos documents. Vous recevrez une notification dès la décision.",
            cta: "Voir ma demande",
            to: "/driver/apply",
          }
        : status === "rejected"
          ? {
              icon: FileWarning,
              tone: "text-destructive",
              title: "Demande refusée",
              desc: profile?.rejected_reason || "Veuillez corriger votre dossier et réessayer.",
              cta: "Refaire ma demande",
              to: "/driver/apply",
            }
          : {
              icon: AlertTriangle,
              tone: "text-destructive",
              title: "Compte chauffeur suspendu",
              desc: profile?.suspended_reason || "Contactez le support pour plus d'informations.",
              cta: "Contacter le support",
              to: "/help",
            };
    const Icon = config.icon;
    return (
      <div className="max-w-md mx-auto">
        <AppHeader
          isDriverMode={true}
          onToggleDriverMode={onToggleDriverMode}
          subtitle="Statut chauffeur"
          amountLabel="Gains du jour"
          amountValue={0}
          location="Conakry"
        />
        <div className="px-4 mt-6">
          <Card className="p-6 text-center space-y-4">
            <div className={`w-16 h-16 rounded-full bg-muted mx-auto flex items-center justify-center ${config.tone}`}>
              <Icon className="w-8 h-8" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-foreground">{config.title}</h2>
              <p className="text-sm text-muted-foreground mt-1">{config.desc}</p>
            </div>
            <Button
              className="w-full h-11 gradient-primary"
              onClick={() => {
                if (config.to === "/help") {
                  Analytics.track("driver.support.opened", { metadata: { from_status: status ?? "none" } });
                }
                navigate(config.to);
              }}
            >
              {config.cta}
            </Button>
            <Button variant="ghost" className="w-full" onClick={onToggleDriverMode}>
              Revenir en mode client
            </Button>
          </Card>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto">
      <AppHeader
        isDriverMode={true}
        onToggleDriverMode={onToggleDriverMode}
        subtitle="Tableau de bord chauffeur"
        amountLabel="Gains du jour"
        amountValue={driverBalance}
        amountLoading={walletLoading}
        notificationCount={queue.length + (current ? 1 : 0)}
        location="Conakry, en service"
      />

      {/* Content */}
      <div className="px-4 mt-5 space-y-4">
        {cashOverLimit && (
          <Card className="p-4 border-destructive/40 bg-destructive/5 flex gap-3 items-start">
            <AlertTriangle className="w-5 h-5 text-destructive flex-shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-foreground">
                Commission cash due : {formatGNF(profile!.cash_debt_gnf)}
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                Vous avez atteint la limite ({formatGNF(profile!.debt_limit_gnf)}). Réglez pour repasser en ligne.
              </p>
            </div>
          </Card>
        )}
        <LiveStrip
          stats={[
            { icon: Users, label: `${queue.length} demandes proches`, bg: "bg-primary/10", tone: "text-primary" },
            { icon: Timer, label: "Temps moyen 12 min", bg: "bg-secondary/20", tone: "text-foreground" },
            { icon: Star, label: `Note ${(profile?.rating ?? 0).toFixed(1)}`, bg: "bg-[hsl(45_90%_55%/0.14)]", tone: "text-[hsl(38_85%_40%)]" },
            { icon: TrendingUp, label: `Acceptation ${Math.round((profile?.accept_rate ?? 0) * 100)}%`, bg: "bg-success/10", tone: "text-success" },
          ]}
        />
        {/* Online toggle — 3 states: Hors ligne / En ligne / Recherche */}
        {(() => {
          const searching = isOnline && !current && !activeTrip;
          const label = !isOnline
            ? toggling ? "Activation…" : "Hors ligne — appuyez pour commencer"
            : searching
              ? "Recherche de courses…"
              : "En ligne — course en cours";
          const tone = !isOnline
            ? "bg-card border border-border text-foreground shadow-card"
            : searching
              ? "gradient-wallet text-primary-foreground ring-glow-primary"
              : "bg-secondary text-secondary-foreground shadow-card";
          return (
            <motion.button
              whileTap={{ scale: 0.97 }}
              onClick={handleTogglePresence}
              disabled={toggling}
              className={`w-full relative flex items-center justify-center gap-3 py-4 rounded-2xl overflow-hidden ${tone} transition-colors disabled:opacity-60`}
            >
              {searching && (
                <motion.span
                  aria-hidden
                  className="absolute inset-0 bg-white/10"
                  animate={{ opacity: [0.05, 0.25, 0.05] }}
                  transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
                />
              )}
              {isOnline ? <Radar className="w-5 h-5 relative" /> : <Power className="w-5 h-5 relative" />}
              <span className="font-bold relative">{label}</span>
            </motion.button>
          );
        })()}

        <DriverDashboard
          todayEarnings={185000}
          weeklyEarnings={1250000}
          completedRides={12}
          onlineHours={6}
        />

        <LiveRidesPanel />

        {isOnline && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-center py-8"
          >
            <div className="w-20 h-20 rounded-full bg-muted mx-auto flex items-center justify-center mb-4">
              <BellRing className="w-10 h-10 text-muted-foreground" />
            </div>
            <h3 className="text-lg font-semibold text-foreground mb-2">
              {queue.length > 0 ? `${queue.length} demande(s) en file` : "En attente de courses"}
            </h3>
            <p className="text-muted-foreground text-sm mb-4">
              Les nouvelles demandes apparaîtront ici
            </p>
            {queue.length > 0 && (
              <Button onClick={triggerNext} variant="outline" className="h-11">
                <BellRing className="w-4 h-4 mr-2" /> Voir la demande suivante
              </Button>
            )}
          </motion.div>
        )}
      </div>

      <IncomingRequestPopup
        request={current}
        onAccept={handleAccept}
        onDecline={handleDecline}
        timeoutSec={20}
      />

      {activeTrip && (
        activeRideId &&
        (typeof window !== "undefined" &&
          (localStorage.getItem("cc_realtime_trip") === "1" ||
            /[?&]trip=v2/.test(window.location.search)))
          ? (
            <DriverActiveTrip
              rideId={activeRideId}
              onClose={() => { setActiveTrip(null); setActiveRideId(null); }}
            />
          )
          : (
            <DriverTripView request={activeTrip} onClose={() => { setActiveTrip(null); setActiveRideId(null); }} />
          )
      )}
    </div>
  );
}
