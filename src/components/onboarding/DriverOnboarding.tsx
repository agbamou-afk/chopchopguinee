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
    body: "Recevez des courses, livraisons et missions dans votre zone.",
    image: sceneWelcome,
    alt: "Chauffeur CHOPCHOP fier devant son véhicule à Conakry",
  },
  {
    id: "missions",
    title: "Acceptez vos missions",
    body: "Moto, Repas, Marché ou colis — choisissez les missions adaptées à vos capacités.",
    image: sceneMission,
    alt: "Cartes de missions différenciées par type sur smartphone",
  },
  {
    id: "navigate",
    title: "Suivez l'itinéraire",
    body: "Voyez le point de récupération, la destination et ouvrez l'itinéraire si besoin.",
    image: sceneNavigate,
    alt: "Carte de navigation avec points de récupération et de dépôt",
  },
  {
    id: "confirm",
    title: "Confirmez chaque étape",
    body: "Récupération, arrivée, livraison — chaque étape protège le client et le coursier.",
    image: sceneDeliver,
    alt: "Confirmation de récupération et de dépôt par QR ou photo",
  },
  {
    id: "earnings",
    title: "Suivez vos gains avec ChopWallet",
    body: "Vos gains restent clairs, visibles et suivis dans votre portefeuille.",
    image: sceneEarnings,
    alt: "Carte ChopWallet montrant les gains du chauffeur",
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