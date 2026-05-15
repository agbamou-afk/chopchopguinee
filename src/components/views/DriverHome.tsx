import { motion, AnimatePresence } from "framer-motion";
import { useEffect, useState } from "react";
import { Power, Radar, Users, AlertTriangle, Clock, ShieldCheck, FileWarning, Wallet, Navigation } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { AppHeader } from "@/components/ui/AppHeader";
import { Button } from "@/components/ui/button";
import { useWallet } from "@/hooks/useWallet";
import { useDriverEarnings } from "@/hooks/useDriverEarnings";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { useAuth } from "@/contexts/AuthContext";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { Sparkles } from "lucide-react";
import { Card } from "@/components/ui/card";
import { formatGNF } from "@/lib/format";
import { useDriverSession } from "@/contexts/DriverSessionContext";

interface DriverHomeProps {
  onToggleDriverMode: () => void;
}

export function DriverHome({ onToggleDriverMode }: DriverHomeProps) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const {
    profile, profileLoading,
    isOnline, toggling, togglePresence, cashOverLimit,
    queue, current, activeTrip,
  } = useDriverSession();
  const { available: driverBalance, loading: walletLoading } = useWallet("driver");
  const e = useDriverEarnings();

  // Demo driver = calm guided showroom. We expose an explicit CTA so the
  // operator can trigger a linked-demo offer on demand instead of having
  // ride popups appear automatically. Hidden in sandbox (which already
  // auto-spawns offers) and in live mode.
  const isDemoDriver = (user?.email ?? "").toLowerCase() === "demo.driver@chopchop.gn";
  const sandboxOn =
    typeof window !== "undefined" &&
    (/[?&]sandbox=1/.test(window.location.search) ||
      /[?&]debug=1/.test(window.location.search));
  const showDemoLauncher = isDemoDriver && !sandboxOn;
  const [demoLaunching, setDemoLaunching] = useState(false);
  const launchDemoRide = async () => {
    if (demoLaunching) return;
    setDemoLaunching(true);
    try {
      const { error } = await supabase.rpc("demo_seed_ride_offer" as never);
      if (error) {
        toast({ title: "Démo", description: error.message });
      } else {
        toast({ title: "Course démo lancée", description: "Une nouvelle demande arrive." });
      }
    } finally {
      setDemoLaunching(false);
    }
  };

  // Rotating activity hints shown while the driver is online and idle.
  // Reassures that the system is actively scanning for nearby demand.
  const ACTIVITY_HINTS = [
    "Analyse des demandes autour de vous…",
    "Conducteurs proches : surveillance de la zone…",
    "Synchronisation avec le réseau CHOP CHOP…",
    "Optimisation des trajets disponibles…",
    "Détection de courses à proximité…",
  ];
  const [hintIdx, setHintIdx] = useState(0);
  const searching = isOnline && !current && !activeTrip;
  useEffect(() => {
    if (!searching) return;
    const id = window.setInterval(
      () => setHintIdx((i) => (i + 1) % ACTIVITY_HINTS.length),
      3500,
    );
    return () => window.clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searching]);

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
        {showDemoLauncher && !activeTrip && !current && queue.length === 0 && (
          <Button
            onClick={launchDemoRide}
            disabled={demoLaunching}
            className="w-full h-12 gradient-primary gap-2"
          >
            <Sparkles className="w-4 h-4" />
            {demoLaunching ? "Préparation…" : "Lancer une course démo"}
          </Button>
        )}
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
        {/* Online toggle — 3 states: Hors ligne / Recherche / En course */}
        {(() => {
          const label = !isOnline
            ? toggling ? "Activation…" : "Hors ligne — appuyez pour commencer"
            : searching
              ? "Recherche de courses"
              : "En ligne — course en cours";
          const tone = !isOnline
            ? "bg-card border border-border text-foreground shadow-card"
            : searching
              ? "gradient-wallet text-primary-foreground ring-glow-primary"
              : "bg-secondary text-secondary-foreground shadow-card";
          return (
            <div className="space-y-2">
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={togglePresence}
                disabled={toggling}
                className={`w-full relative flex items-center justify-center gap-3 py-4 rounded-2xl overflow-hidden ${tone} transition-colors disabled:opacity-60`}
              >
                {/* Subtle outward pulse halo while actively searching */}
                {searching && (
                  <>
                    <motion.span
                      aria-hidden
                      className="pointer-events-none absolute inset-0 rounded-2xl border-2 border-white/40"
                      animate={{ scale: [1, 1.04, 1], opacity: [0.5, 0, 0.5] }}
                      transition={{ duration: 2.2, repeat: Infinity, ease: "easeOut" }}
                    />
                    <motion.span
                      aria-hidden
                      className="absolute inset-0 bg-white/10"
                      animate={{ opacity: [0.05, 0.25, 0.05] }}
                      transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
                    />
                  </>
                )}
                {isOnline ? (
                  <span className="relative inline-flex">
                    {searching && (
                      <motion.span
                        aria-hidden
                        className="absolute inset-0 rounded-full bg-white/30"
                        animate={{ scale: [1, 1.8], opacity: [0.6, 0] }}
                        transition={{ duration: 1.6, repeat: Infinity, ease: "easeOut" }}
                      />
                    )}
                    <Radar className="w-5 h-5 relative" />
                  </span>
                ) : (
                  <Power className="w-5 h-5 relative" />
                )}
                <span className="font-bold relative inline-flex items-center">
                  {label}
                  {searching && (
                    <motion.span
                      aria-hidden
                      className="ml-1 inline-flex"
                      animate={{ opacity: [0.4, 1, 0.4] }}
                      transition={{ duration: 1.4, repeat: Infinity }}
                    >
                      …
                    </motion.span>
                  )}
                </span>
              </motion.button>

              {/* Lightweight rotating activity hint — proves the app is alive */}
              <AnimatePresence mode="wait">
                {searching && (
                  <motion.div
                    key={hintIdx}
                    initial={{ opacity: 0, y: 4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -4 }}
                    transition={{ duration: 0.35 }}
                    className="flex items-center justify-center gap-2 text-[11px] text-muted-foreground"
                  >
                    <span className="relative inline-flex h-1.5 w-1.5">
                      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary/70" />
                      <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-primary" />
                    </span>
                    {ACTIVITY_HINTS[hintIdx]}
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          );
        })()}

        {/* Operational chips: today earnings + nearby demand */}
        <div className="grid grid-cols-2 gap-3">
          <Card className="p-3.5 flex items-center gap-3 border-border/50 shadow-card">
            <div className="p-2.5 rounded-2xl bg-primary/10 ring-1 ring-primary/15">
              <Wallet className="w-4 h-4 text-primary" />
            </div>
            <div className="min-w-0">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Aujourd'hui</p>
              <p className="text-sm font-bold text-foreground truncate tabular-nums">{formatGNF(e.todayGnf)}</p>
            </div>
          </Card>
          <Card className="p-3.5 flex items-center gap-3 relative overflow-hidden border-border/50 shadow-card">
            <div className="p-2.5 rounded-2xl bg-success/10 ring-1 ring-success/15 relative">
              <Users className="w-4 h-4 text-success" />
              {isOnline && (
                <span className="absolute -top-0.5 -right-0.5 inline-flex h-2 w-2">
                  <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-success/70" />
                  <span className="relative inline-flex h-2 w-2 rounded-full bg-success" />
                </span>
              )}
            </div>
            <div className="min-w-0">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Demandes</p>
              <p className="text-sm font-bold text-foreground truncate">
                {queue.length > 0
                  ? `${queue.length} ${queue.length > 1 ? "proches" : "proche"}`
                  : isOnline ? "À l'écoute…" : "Hors ligne"}
              </p>
            </div>
          </Card>
        </div>

        {/* Active ride card OR demand heatmap */}
        {activeTrip && (
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
        )}
      </div>

    </div>
  );
}
