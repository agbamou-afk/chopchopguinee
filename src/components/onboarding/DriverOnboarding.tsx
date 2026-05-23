import { useEffect, useState } from "react";
import sceneWelcome from "@/assets/onboarding/scene-driver-welcome.jpg";
import sceneMission from "@/assets/onboarding/scene-driver-mission.jpg";
import sceneNavigate from "@/assets/onboarding/scene-driver-navigate.jpg";
import sceneDeliver from "@/assets/onboarding/scene-driver-deliver.jpg";
import sceneEarnings from "@/assets/onboarding/scene-driver-earnings.jpg";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { OnboardingStorybook, type StorybookSlide } from "./OnboardingStorybook";

interface Props {
  onDone: () => void;
}

const SLIDES: StorybookSlide[] = [
  {
    id: "welcome",
    title: "Bienvenue partenaire CHOPCHOP",
    body: "Rejoignez une communauté de chauffeurs de confiance et gagnez plus chaque jour.",
    image: sceneWelcome,
    alt: "Chauffeur CHOPCHOP fier devant son véhicule à Conakry",
  },
  {
    id: "missions",
    title: "Recevez des courses et missions",
    body: "Acceptez en un clic. Plus vous roulez, plus vous gagnez.",
    image: sceneMission,
    alt: "Smartphone avec une nouvelle course à accepter",
  },
  {
    id: "navigate",
    title: "Naviguez vers votre client",
    body: "Suivez l'itinéraire, arrivez à l'heure, offrez une meilleure expérience.",
    image: sceneNavigate,
    alt: "Vue de navigation depuis le tableau de bord",
  },
  {
    id: "deliver",
    title: "Livrez, déposez, envoyez",
    body: "Livrez des repas, des courses ou des colis avec Marché, Repas et Envoyer.",
    image: sceneDeliver,
    alt: "Coursier CHOPCHOP livrant des sacs",
  },
  {
    id: "earnings",
    title: "Vos gains, votre avenir",
    body: "Recevez vos paiements dans ChopWallet et développez plus d'opportunités.",
    image: sceneEarnings,
    alt: "Écran ChopWallet montrant les gains",
  },
];

export function DriverOnboarding({ onDone }: Props) {
  const [index, setIndex] = useState(0);
  const isLast = index === SLIDES.length - 1;

  useEffect(() => {
    Analytics.track("driver_onboarding.viewed");
  }, []);

  useEffect(() => {
    Analytics.track("driver_onboarding.step.viewed", {
      metadata: { step: index, key: SLIDES[index].id },
    });
  }, [index]);

  const next = () => {
    if (isLast) {
      Analytics.track("driver_onboarding.completed", { metadata: { steps: SLIDES.length } });
      onDone();
    } else setIndex((i) => i + 1);
  };
  const prev = () => setIndex((i) => Math.max(0, i - 1));
  const skip = () => {
    Analytics.track("driver_onboarding.skipped", {
      metadata: { at_step: index, key: SLIDES[index].id },
    });
    onDone();
  };

  return (
    <OnboardingStorybook
      ariaLabel="Bienvenue chauffeur CHOPCHOP"
      slides={SLIDES}
      index={index}
      primaryLabel="Commencer"
      footerCaption="CHOPCHOP · Chauffeur · Conakry"
      onNext={next}
      onPrev={prev}
      onSkip={skip}
    />
  );
}

export const DRIVER_ONBOARDING_DONE_KEY = "cc_driver_onboarding_done";
export const DRIVER_ONBOARDING_REPLAY_EVENT = "cc:replay-driver-onboarding";