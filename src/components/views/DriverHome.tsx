import { motion } from "framer-motion";
import { Power, Radar, Users, AlertTriangle, Clock, ShieldCheck, FileWarning, Wallet, MapPin, Navigation } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { AppHeader } from "@/components/ui/AppHeader";
import { Button } from "@/components/ui/button";
import { useWallet } from "@/hooks/useWallet";
import { useDriverEarnings } from "@/hooks/useDriverEarnings";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { Card } from "@/components/ui/card";
import { formatGNF } from "@/lib/format";
import { ChopMap, HeatmapLayer } from "@/components/map";
import { useDriverSession } from "@/contexts/DriverSessionContext";

interface DriverHomeProps {
  onToggleDriverMode: () => void;
}

export function DriverHome({ onToggleDriverMode }: DriverHomeProps) {
  const navigate = useNavigate();
  const {
    profile, profileLoading,
    isOnline, toggling, togglePresence, cashOverLimit,
    queue, current, activeTrip,
  } = useDriverSession();
  const { available: driverBalance, loading: walletLoading } = useWallet("driver");
  const e = useDriverEarnings();

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

        {/* Operational chips: today earnings + nearby demand */}
        <div className="grid grid-cols-2 gap-3">
          <Card className="p-3 flex items-center gap-3">
            <div className="p-2 rounded-xl bg-primary/10">
              <Wallet className="w-4 h-4 text-primary" />
            </div>
            <div className="min-w-0">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Aujourd'hui</p>
              <p className="text-sm font-bold text-foreground truncate">{formatGNF(e.todayGnf)}</p>
            </div>
          </Card>
          <Card className="p-3 flex items-center gap-3">
            <div className="p-2 rounded-xl bg-success/10">
              <Users className="w-4 h-4 text-success" />
            </div>
            <div className="min-w-0">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Demandes</p>
              <p className="text-sm font-bold text-foreground truncate">
                {queue.length} {queue.length > 1 ? "proches" : "proche"}
              </p>
            </div>
          </Card>
        </div>

        {/* Active ride card OR demand heatmap */}
        {activeTrip ? (
          <Card className="p-4 border-primary/40 bg-primary/5">
            <div className="flex items-start gap-3">
              <div className="p-2 rounded-xl bg-primary/15 mt-0.5">
                <Navigation className="w-5 h-5 text-primary" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[11px] uppercase tracking-wide text-primary font-semibold">Course en cours</p>
                <p className="text-sm font-bold text-foreground truncate mt-0.5">
                  {activeTrip.pickup} → {activeTrip.destination}
                </p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {formatGNF(activeTrip.estimatedPrice)} · {activeTrip.distance}
                </p>
              </div>
              <Button size="sm" className="gradient-primary" onClick={() => { /* trip overlay opens via state */ }}>
                Ouvrir
              </Button>
            </div>
          </Card>
        ) : (
          <Card className="overflow-hidden">
            <div className="px-4 pt-3 pb-2 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <MapPin className="w-4 h-4 text-primary" />
                <p className="text-sm font-semibold text-foreground">Demande à proximité</p>
              </div>
              <span className="text-[11px] text-muted-foreground">Conakry</span>
            </div>
            <div className="relative h-44 bg-muted">
              <ChopMap
                className="absolute inset-0 w-full h-full"
                interactive={false}
                initialView={{ longitude: -13.6773, latitude: 9.6412, zoom: 11.5 }}
              >
                <HeatmapLayer
                  points={[
                    { lng: -13.6773, lat: 9.6412, weight: 1 },
                    { lng: -13.6850, lat: 9.5350, weight: 0.85 },
                    { lng: -13.6500, lat: 9.5800, weight: 0.7 },
                    { lng: -13.7000, lat: 9.6200, weight: 0.6 },
                    { lng: -13.6650, lat: 9.6100, weight: 0.5 },
                    { lng: -13.6300, lat: 9.5500, weight: 0.45 },
                  ]}
                />
              </ChopMap>
              {!isOnline && (
                <div className="absolute inset-0 bg-background/70 backdrop-blur-[2px] flex items-center justify-center">
                  <p className="text-xs text-muted-foreground px-3 text-center">
                    Passez en ligne pour recevoir des demandes
                  </p>
                </div>
              )}
            </div>
          </Card>
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
