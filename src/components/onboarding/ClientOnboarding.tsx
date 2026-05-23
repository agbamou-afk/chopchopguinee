import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import sceneWelcome from "@/assets/onboarding/scene-welcome.jpg";
import sceneMoto from "@/assets/onboarding/scene-moto.jpg";
import sceneMarche from "@/assets/onboarding/scene-marche.jpg";
import sceneRepas from "@/assets/onboarding/scene-repas.jpg";
import sceneWallet from "@/assets/onboarding/scene-wallet.jpg";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import walletIcon from "@/assets/icons/wallet.png";
import scannerIcon from "@/assets/icons/scanner.png";
import envoyerIcon from "@/assets/icons/envoyer.png";
import choppayIcon from "@/assets/icons/choppay.png";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { OnboardingStorybook, type StorybookSlide } from "./OnboardingStorybook";

interface Props {
  onDone: () => void;
}

/**
 * Ecosystem icon cluster shown over the welcome scene. Uses ONLY the native
 * CHOPCHOP service icon family (raster PNGs from src/assets/icons), so it
 * matches the in-app PrimaryActionGrid / QuickActions language.
 */
const ECOSYSTEM_ICONS = [
  { src: motoIcon,    label: "Moto" },
  { src: toktokIcon,  label: "TokTok" },
  { src: repasIcon,   label: "Repas" },
  { src: marcheIcon,  label: "Marché" },
  { src: walletIcon,  label: "ChopWallet" },
  { src: scannerIcon, label: "Scanner" },
  { src: envoyerIcon, label: "Envoyer" },
  { src: choppayIcon, label: "ChopPay" },
] as const;

function EcosystemCluster() {
  // 4×2 grid of floating native CHOPCHOP icons, anchored upper-center so it
  // never collides with the title block or floating controls below.
  return (
    <div className="absolute inset-x-0 top-[max(4.5rem,env(safe-area-inset-top))] flex justify-center px-6">
      <motion.div
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
        className="grid grid-cols-4 gap-2.5 max-w-xs"
      >
        {ECOSYSTEM_ICONS.map((icon, i) => (
          <motion.div
            key={icon.label}
            initial={{ opacity: 0, y: 6, scale: 0.92 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ duration: 0.35, delay: 0.15 + i * 0.05, ease: [0.22, 1, 0.36, 1] }}
            className="w-14 h-14 rounded-2xl bg-card/85 backdrop-blur border border-border/60 shadow-soft flex items-center justify-center overflow-hidden"
          >
            <img
              src={icon.src}
              alt={icon.label}
              loading="lazy"
              width={1024}
              height={1024}
              className="w-12 h-12 object-contain scale-[1.4]"
            />
          </motion.div>
        ))}
      </motion.div>
    </div>
  );
}

const SLIDES: StorybookSlide[] = [
  {
    id: "welcome",
    title: "Bienvenue sur CHOPCHOP Conakry",
    body: "Votre app locale pour vous déplacer, manger, acheter et envoyer — en toute simplicité.",
    image: sceneWelcome,
    alt: "Conakry au coucher du soleil",
    overlay: <EcosystemCluster />,
  },
  {
    id: "ride",
    title: "Commandez un Moto ou un TokTok",
    body: "Déplacez-vous vite et en sécurité où que vous alliez à Conakry.",
    image: sceneMoto,
    alt: "Moto et TokTok dans les rues de Conakry",
  },
  {
    id: "repas",
    title: "Commandez avec Chop Repas",
    body: "Vos plats préférés livrés chauds, rapidement, chez vous.",
    image: sceneRepas,
    alt: "Repas chaud livré",
  },
  {
    id: "marche",
    title: "Faites vos courses avec Chop Marché",
    body: "Produits frais, boutiques locales et marchés livrés à votre porte.",
    image: sceneMarche,
    alt: "Marché de Conakry",
  },
  {
    id: "wallet",
    title: "Payez, envoyez, gérez avec ChopWallet et ChopPay",
    body: "Votre portefeuille sécurisé pour payer, envoyer et recevoir partout.",
    image: sceneWallet,
    alt: "ChopWallet sur smartphone",
  },
];

export function ClientOnboarding({ onDone }: Props) {
  const [index, setIndex] = useState(0);
  const isLast = index === SLIDES.length - 1;

  useEffect(() => {
    Analytics.track("onboarding.viewed");
  }, []);

  useEffect(() => {
    Analytics.track("onboarding.step.viewed", {
      metadata: { step: index, key: SLIDES[index].id },
    });
  }, [index]);

  const next = () => {
    if (isLast) {
      Analytics.track("onboarding.completed", { metadata: { steps: SLIDES.length } });
      onDone();
    } else setIndex((i) => i + 1);
  };
  const prev = () => setIndex((i) => Math.max(0, i - 1));

  const skip = () => {
    Analytics.track("onboarding.skipped", { metadata: { at_step: index, key: SLIDES[index].id } });
    onDone();
  };

  return (
    <OnboardingStorybook
      ariaLabel="Bienvenue sur CHOPCHOP"
      slides={SLIDES}
      index={index}
      primaryLabel="Commencer"
      footerCaption="CHOPCHOP · Conakry"
      onNext={next}
      onPrev={prev}
      onSkip={skip}
    />
  );
}

export const ONBOARDING_DONE_KEY = "cc_client_onboarding_done";
export const ONBOARDING_REPLAY_EVENT = "cc:replay-onboarding";