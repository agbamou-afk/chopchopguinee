import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import logo from "@/assets/logo.png";
import sceneMoto from "@/assets/onboarding/scene-moto.png";
import sceneMarche from "@/assets/onboarding/scene-marche.png";
import sceneRepas from "@/assets/onboarding/scene-repas.png";
import sceneWallet from "@/assets/onboarding/scene-wallet.png";
import { useLowDataMode } from "@/hooks/useLowDataMode";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { OnboardingShell } from "./OnboardingShell";

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
    <div className="relative w-full h-full rounded-3xl overflow-hidden card-warm">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam z-10" aria-hidden />
      <motion.img
        src={src}
        alt={alt}
        loading="lazy"
        width={1024}
        height={768}
        className="absolute inset-0 w-full h-full object-cover"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: animated ? 0.45 : 0, ease: [0.22, 1, 0.36, 1] }}
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
    <div className="relative w-full h-full rounded-3xl overflow-hidden gradient-wallet text-primary-foreground border border-primary/30 flex flex-col items-center justify-center text-center px-6 ring-glow-primary">
      <div className="pointer-events-none absolute -top-12 -right-10 w-44 h-44 rounded-full bg-secondary/30 blur-3xl" aria-hidden />
      <div className="pointer-events-none absolute -bottom-12 -left-10 w-40 h-40 rounded-full bg-white/10 blur-3xl" aria-hidden />
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[2px] kente-stripe" aria-hidden />
      <motion.img
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
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

  return (
    <OnboardingShell
      ariaLabel="Bienvenue sur CHOP CHOP"
      steps={SCENES.length}
      index={index}
      isLast={isLast}
      sceneKey={scene.key}
      scene={<Scene scene={scene.key} animated={animated} />}
      title={scene.title}
      caption={scene.caption}
      primaryLabel="Entrer dans CHOP CHOP"
      footerCaption="CHOP CHOP · Conakry"
      onNext={next}
      onPrev={prev}
      onClose={skip}
    />
  );
}

export const ONBOARDING_DONE_KEY = "cc_client_onboarding_done";
export const ONBOARDING_REPLAY_EVENT = "cc:replay-onboarding";