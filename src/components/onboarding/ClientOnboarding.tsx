import { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Bike,
  ShoppingBag,
  UtensilsCrossed,
  Wallet,
  MapPin,
  Truck,
  Plus,
  Receipt,
  ChevronRight,
  X,
} from "lucide-react";
import logo from "@/assets/logo.png";
import { useLowDataMode } from "@/hooks/useLowDataMode";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface Props {
  onDone: () => void;
}

type SceneKey = "ride" | "marche" | "repas" | "wallet" | "final";

const SCENES: Array<{ key: SceneKey; title: string; caption: string }> = [
  { key: "ride", title: "Course", caption: "Commandez une moto en quelques secondes." },
  { key: "marche", title: "Marché", caption: "Achetez au Marché et faites livrer." },
  { key: "repas", title: "Repas", caption: "Commandez vos repas préférés." },
  { key: "wallet", title: "CHOPWallet", caption: "Rechargez votre CHOPWallet et payez simplement avec CHOPPay." },
  { key: "final", title: "Bienvenue", caption: "Tout. Partout. Pour Tous." },
];

function RideScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-56 rounded-3xl overflow-hidden card-warm">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      {/* fake map grid */}
      <div className="absolute inset-0 opacity-40"
        style={{
          backgroundImage:
            "linear-gradient(hsl(var(--border)) 1px, transparent 1px), linear-gradient(90deg, hsl(var(--border)) 1px, transparent 1px)",
          backgroundSize: "24px 24px",
        }} />
      {/* route line */}
      <svg className="absolute inset-0 w-full h-full" viewBox="0 0 320 220" preserveAspectRatio="none">
        <motion.path
          d="M40,170 C100,170 140,80 280,60"
          stroke="hsl(var(--primary))"
          strokeWidth="4"
          strokeLinecap="round"
          fill="none"
          initial={{ pathLength: 0 }}
          animate={{ pathLength: animated ? 1 : 1 }}
          transition={{ duration: animated ? 1.4 : 0, ease: "easeInOut" }}
        />
      </svg>
      {/* pickup pin */}
      <motion.div
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: animated ? 0.1 : 0 }}
        className="absolute"
        style={{ left: "calc(40px / 320 * 100%)", top: "calc(170px / 220 * 100% - 28px)" }}
      >
        <div className="w-7 h-7 rounded-full bg-primary text-primary-foreground flex items-center justify-center shadow-lg">
          <MapPin className="w-4 h-4" />
        </div>
      </motion.div>
      {/* driver moto moving */}
      <motion.div
        initial={{ left: "82%" }}
        animate={{ left: animated ? "20%" : "20%" }}
        transition={{ duration: animated ? 1.6 : 0, ease: "easeInOut", delay: animated ? 0.4 : 0 }}
        className="absolute top-[calc(60px/220*100%-14px)]"
      >
        <div className="w-9 h-9 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center shadow-lg">
          <Bike className="w-5 h-5" />
        </div>
      </motion.div>
    </div>
  );
}

function MarcheScene({ animated }: { animated: boolean }) {
  const items = [0, 1, 2, 3];
  return (
    <div className="relative w-full h-56 rounded-3xl overflow-hidden card-warm p-4">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <div className="grid grid-cols-2 gap-3">
        {items.map((i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: animated ? 0.05 * i : 0 }}
            className={`relative h-20 rounded-2xl border ${i === 1 ? "border-primary ring-2 ring-primary/40" : "border-border/60"} bg-muted/40 flex items-center justify-center`}
          >
            <ShoppingBag className="w-6 h-6 text-muted-foreground" />
            {i === 1 && (
              <motion.div
                initial={{ scale: 0, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: animated ? 0.6 : 0, type: "spring", stiffness: 220 }}
                className="absolute -top-2 -right-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-primary text-primary-foreground text-[10px] font-bold shadow"
              >
                <Truck className="w-3 h-3" /> Livraison
              </motion.div>
            )}
          </motion.div>
        ))}
      </div>
    </div>
  );
}

function RepasScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-56 rounded-3xl overflow-hidden card-warm p-4 space-y-3">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center gap-3 p-3 rounded-2xl bg-muted/40 border border-border/60"
      >
        <div className="w-12 h-12 halo-conakry shadow-card flex items-center justify-center relative">
          <UtensilsCrossed className="w-6 h-6 text-primary relative z-10" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold text-foreground">Le Damier</p>
          <p className="text-[11px] text-muted-foreground">Riz gras · 25 min</p>
        </div>
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ delay: animated ? 0.5 : 0, type: "spring", stiffness: 240 }}
          className="w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center shadow"
        >
          <Plus className="w-4 h-4" />
        </motion.div>
      </motion.div>
      <div className="relative h-24 rounded-2xl bg-gradient-to-br from-primary/10 to-secondary/10 overflow-hidden">
        <svg className="absolute inset-0 w-full h-full" viewBox="0 0 320 96" preserveAspectRatio="none">
          <motion.path
            d="M20,76 C90,76 140,20 300,20"
            stroke="hsl(var(--primary))"
            strokeWidth="3"
            strokeDasharray="6 6"
            fill="none"
            initial={{ pathLength: 0 }}
            animate={{ pathLength: 1 }}
            transition={{ duration: animated ? 1.2 : 0, delay: animated ? 0.3 : 0 }}
          />
        </svg>
        <motion.div
          initial={{ left: "5%" }}
          animate={{ left: animated ? "85%" : "85%" }}
          transition={{ duration: animated ? 1.4 : 0, delay: animated ? 0.4 : 0, ease: "easeInOut" }}
          className="absolute top-2"
        >
          <div className="w-9 h-9 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center shadow-lg">
            <Bike className="w-5 h-5" />
          </div>
        </motion.div>
      </div>
    </div>
  );
}

function WalletScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-56 rounded-3xl overflow-hidden card-warm p-4 space-y-3">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        className="rounded-2xl gradient-wallet p-4 text-primary-foreground shadow-wallet relative overflow-hidden"
      >
        <div className="pointer-events-none absolute inset-x-4 top-0 h-px bg-gradient-to-r from-transparent via-secondary to-transparent" aria-hidden />
        <p className="text-[10px] uppercase tracking-[0.22em] font-bold opacity-90">Solde CHOPWallet</p>
        <p className="text-2xl font-extrabold tracking-tight">125 000 GNF</p>
        <div className="flex items-center gap-2 mt-2">
          <div className="inline-flex items-center gap-1 px-2 py-1 rounded-full bg-white/15 ring-1 ring-white/15 text-[11px] font-semibold">
            <Plus className="w-3 h-3" /> Recharger
          </div>
          <div className="inline-flex items-center gap-1 px-2 py-1 rounded-full bg-secondary/90 text-secondary-foreground text-[11px] font-bold">
            <Wallet className="w-3 h-3" /> Payer · CHOPPay
          </div>
        </div>
      </motion.div>
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: animated ? 0.5 : 0 }}
        className="flex items-center gap-3 p-3 rounded-2xl surface-money"
      >
        <div className="w-9 h-9 rounded-xl bg-success/15 flex items-center justify-center">
          <Receipt className="w-5 h-5 text-success" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold text-foreground">Recharge Orange Money</p>
          <p className="text-[11px] text-muted-foreground">+50 000 GNF · à l'instant</p>
        </div>
      </motion.div>
    </div>
  );
}

function FinalScene() {
  return (
    <div className="relative w-full h-56 rounded-3xl overflow-hidden gradient-wallet text-primary-foreground border border-primary/30 flex flex-col items-center justify-center text-center px-6 ring-glow-primary">
      <div className="pointer-events-none absolute -top-12 -right-10 w-44 h-44 rounded-full bg-secondary/30 blur-3xl" aria-hidden />
      <div className="pointer-events-none absolute -bottom-12 -left-10 w-40 h-40 rounded-full bg-white/10 blur-3xl" aria-hidden />
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[2px] kente-stripe" aria-hidden />
      <motion.img
        initial={{ scale: 0.7, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ type: "spring", stiffness: 180 }}
        src={logo}
        alt="CHOP CHOP"
        className="w-20 h-20 rounded-2xl shadow-elevated mb-3 bg-white/95 p-2"
      />
      <p className="text-lg font-extrabold tracking-tight">CHOP CHOP</p>
      <p className="text-sm opacity-90 mt-1">Tout. Partout. Pour Tous.</p>
    </div>
  );
}

function Scene({ scene, animated }: { scene: SceneKey; animated: boolean }) {
  switch (scene) {
    case "ride": return <RideScene animated={animated} />;
    case "marche": return <MarcheScene animated={animated} />;
    case "repas": return <RepasScene animated={animated} />;
    case "wallet": return <WalletScene animated={animated} />;
    case "final": return <FinalScene />;
  }
}

export function ClientOnboarding({ onDone }: Props) {
  const [index, setIndex] = useState(0);
  const { low } = useLowDataMode();
  const animated = !low;
  const scene = SCENES[index];
  const isLast = index === SCENES.length - 1;

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, []);

  useEffect(() => {
    Analytics.track("onboarding.viewed");
  }, []);

  useEffect(() => {
    Analytics.track("onboarding.step.viewed", {
      metadata: { step: index, key: SCENES[index].key },
    });
  }, [index]);

  const next = () => {
    if (isLast) {
      Analytics.track("onboarding.completed", { metadata: { steps: SCENES.length } });
      onDone();
    } else setIndex((i) => i + 1);
  };
  const prev = () => setIndex((i) => Math.max(0, i - 1));

  const skip = () => {
    Analytics.track("onboarding.skipped", { metadata: { at_step: index, key: SCENES[index].key } });
    onDone();
  };

  const dots = useMemo(() => SCENES.map((_, i) => i), []);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-[80] bg-app-conakry flex flex-col touch-none relative"
      role="dialog"
      aria-modal="true"
      aria-label="Bienvenue sur CHOP CHOP"
    >
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[2px] kente-stripe z-10" aria-hidden />
      <div className="flex items-center justify-end px-4 pt-[max(1rem,env(safe-area-inset-top))]">
        <button
          onClick={skip}
          className="inline-flex items-center justify-center w-10 h-10 rounded-full text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
          aria-label="Fermer"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      <div
        className="flex-1 flex flex-col justify-center max-w-md w-full mx-auto px-5"
        onClick={(e) => e.stopPropagation()}
      >
        <AnimatePresence mode="wait">
          <motion.div
            key={scene.key}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.25 }}
            drag="x"
            dragConstraints={{ left: 0, right: 0 }}
            dragElastic={0.2}
            onDragEnd={(_, info) => {
              if (info.offset.x < -60) next();
              else if (info.offset.x > 60) prev();
            }}
          >
            <Scene scene={scene.key} animated={animated} />
            <div className="text-center mt-5">
              <p className="text-[11px] uppercase tracking-widest font-bold text-primary">{scene.title}</p>
              <p className="text-lg font-extrabold text-foreground mt-1">{scene.caption}</p>
            </div>
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] space-y-3 max-w-md w-full mx-auto">
        <div className="flex items-center justify-center gap-1.5">
          {dots.map((i) => (
            <span
              key={i}
              className={`h-1.5 rounded-full transition-all duration-300 ease-out ${
                i === index ? "w-7 bg-gradient-to-r from-primary to-secondary" : "w-1.5 bg-border"
              }`}
            />
          ))}
        </div>
        <button
          onClick={next}
          className="w-full inline-flex items-center justify-center gap-2 px-4 py-4 min-h-[56px] rounded-2xl gradient-cta text-primary-foreground font-bold text-base hover:opacity-95 active:scale-[0.985] transition"
        >
          {isLast ? "Explorer CHOP CHOP" : (<>Suivant <ChevronRight className="w-5 h-5" /></>)}
        </button>
        <p className="text-center text-[10px] uppercase tracking-[0.22em] text-muted-foreground/80">
          CHOP CHOP · Conakry
        </p>
      </div>
    </motion.div>
  );
}

export const ONBOARDING_DONE_KEY = "cc_client_onboarding_done";
export const ONBOARDING_REPLAY_EVENT = "cc:replay-onboarding";