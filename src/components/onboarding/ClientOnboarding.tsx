import { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronRight, X } from "lucide-react";
import logo from "@/assets/logo.png";
import sceneMoto from "@/assets/onboarding/scene-moto.png";
import sceneMarche from "@/assets/onboarding/scene-marche.png";
import sceneRepas from "@/assets/onboarding/scene-repas.png";
import sceneWallet from "@/assets/onboarding/scene-wallet.png";
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

function EditorialScene({ src, alt, animated }: { src: string; alt: string; animated: boolean }) {
  return (
    <div className="relative w-full h-56 rounded-3xl overflow-hidden card-warm">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam z-10" aria-hidden />
      <motion.img
        src={src}
        alt={alt}
        loading="lazy"
        width={1024}
        height={768}
        className="absolute inset-0 w-full h-full object-cover"
        initial={{ scale: animated ? 1.04 : 1, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: animated ? 0.6 : 0, ease: [0.22, 1, 0.36, 1] }}
      />
      <div
        className="pointer-events-none absolute inset-0"
        aria-hidden
        style={{
          background:
            "linear-gradient(180deg, transparent 55%, hsl(var(--background) / 0.55) 100%)",
        }}
      />
    </div>
  );
}

function RideScene({ animated }: { animated: boolean }) {
  return <EditorialScene src={sceneMoto} alt="Course en moto à Conakry" animated={animated} />;
}
function MarcheScene({ animated }: { animated: boolean }) {
  return <EditorialScene src={sceneMarche} alt="Marché de Conakry" animated={animated} />;
}
function RepasScene({ animated }: { animated: boolean }) {
  return <EditorialScene src={sceneRepas} alt="Repas livré" animated={animated} />;
}
function WalletScene({ animated }: { animated: boolean }) {
  return <EditorialScene src={sceneWallet} alt="CHOPWallet et CHOPPay" animated={animated} />;
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