import { useState } from "react";
import { motion } from "framer-motion";
import {
  Power, Bell, MapPin, Flag, Flame, Wallet, QrCode, Check,
} from "lucide-react";
import logo from "@/assets/logo.png";
import { useLowDataMode } from "@/hooks/useLowDataMode";
import { OnboardingShell } from "./OnboardingShell";

interface Props {
  onDone: () => void;
}

type SceneKey = "online" | "accept" | "pickup" | "complete" | "heatmap" | "final";

const SCENES: Array<{ key: SceneKey; title: string; caption: string }> = [
  { key: "online",   title: "Passez en ligne", caption: "Activez votre statut pour recevoir des courses." },
  { key: "accept",   title: "Accepter une course", caption: "Une demande arrive — acceptez en un tap." },
  { key: "pickup",   title: "Prise en charge",  caption: "Confirmez le pickup avec le client." },
  { key: "complete", title: "Gains & CHOPWallet", caption: "Recevez vos gains directement dans votre CHOPWallet via CHOPPay." },
  { key: "heatmap",  title: "Zones actives",    caption: "Placez-vous là où la demande est la plus forte." },
  { key: "final",    title: "Prêt à conduire",  caption: "Conduisez mieux. Gagnez mieux." },
];

function OnlineScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-full rounded-3xl overflow-hidden card-warm flex items-center justify-center">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: animated ? 0.4 : 0, ease: [0.22, 1, 0.36, 1] }}
        className="relative flex flex-col items-center gap-3"
      >
        <div className="relative">
          <span className="absolute inset-0 rounded-full bg-success/30 animate-ping" />
          <div className="relative w-20 h-20 rounded-full bg-success text-white flex items-center justify-center shadow-lg">
            <Power className="w-9 h-9" />
          </div>
        </div>
        <span className="px-3 py-1 rounded-full bg-success/15 text-success text-xs font-bold uppercase tracking-wide">
          En ligne
        </span>
      </motion.div>
    </div>
  );
}

function AcceptScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-full rounded-3xl overflow-hidden card-warm">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <motion.div
        initial={{ y: 60, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: animated ? 0.45 : 0, delay: animated ? 0.1 : 0, ease: [0.22, 1, 0.36, 1] }}
        className="absolute left-3 right-3 bottom-3 rounded-2xl bg-card border border-border shadow-lg p-3 space-y-2"
      >
        <div className="flex items-center gap-2">
          <Bell className="w-4 h-4 text-primary" />
          <p className="text-[11px] uppercase tracking-wide font-bold text-primary">Nouvelle course</p>
        </div>
        <p className="text-sm font-bold text-foreground">Ratoma → Kaloum · 8 500 GNF</p>
        <motion.div
          animate={animated ? { scale: [1, 1.04, 1] } : {}}
          transition={{ duration: 1.4, repeat: Infinity }}
          className="w-full text-center py-2 rounded-xl bg-primary text-primary-foreground text-sm font-bold shadow"
        >
          Accepter
        </motion.div>
      </motion.div>
    </div>
  );
}

function PickupScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-full rounded-3xl overflow-hidden card-warm">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <div className="absolute inset-0 opacity-40"
        style={{
          backgroundImage:
            "linear-gradient(hsl(var(--border)) 1px, transparent 1px), linear-gradient(90deg, hsl(var(--border)) 1px, transparent 1px)",
          backgroundSize: "24px 24px",
        }} />
      <svg className="absolute inset-0 w-full h-full" viewBox="0 0 320 220" preserveAspectRatio="none">
        <motion.path
          d="M30,180 C100,180 160,90 290,70"
          stroke="hsl(var(--primary))"
          strokeWidth="4"
          strokeLinecap="round"
          fill="none"
          initial={{ pathLength: 0 }}
          animate={{ pathLength: 1 }}
          transition={{ duration: animated ? 1.0 : 0, ease: [0.22, 1, 0.36, 1] }}
        />
      </svg>
      <motion.div
        initial={{ opacity: 0, y: -6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: animated ? 0.6 : 0, duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
        className="absolute right-3 top-3 bg-card border border-border rounded-2xl p-2 shadow-lg flex items-center gap-2"
      >
        <div className="w-10 h-10 rounded-lg bg-white border border-border flex items-center justify-center">
          <QrCode className="w-6 h-6 text-foreground" />
        </div>
        <div>
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Code</p>
          <p className="text-sm font-bold tabular-nums tracking-[0.2em]">A1B2C3</p>
        </div>
      </motion.div>
      <motion.div
        initial={{ left: "8%", top: "78%" }}
        animate={{ left: "82%", top: "26%" }}
        transition={{ duration: animated ? 1.2 : 0, ease: [0.22, 1, 0.36, 1] }}
        className="absolute"
      >
        <div className="w-9 h-9 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center shadow-lg">
          <MapPin className="w-5 h-5" />
        </div>
      </motion.div>
    </div>
  );
}

function CompleteScene({ animated }: { animated: boolean }) {
  return (
    <div className="relative w-full h-full rounded-3xl overflow-hidden card-warm p-4 flex flex-col items-center justify-center gap-3">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <motion.div
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: animated ? 0.05 : 0, duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
        className="w-14 h-14 halo-conakry shadow-card flex items-center justify-center relative"
      >
        <Check className="w-8 h-8 text-success relative z-10" />
      </motion.div>
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: animated ? 0.4 : 0 }}
        className="rounded-2xl gradient-wallet text-primary-foreground px-5 py-3 shadow-wallet flex items-center gap-3 relative overflow-hidden"
      >
        <div className="pointer-events-none absolute inset-x-4 top-0 h-px bg-gradient-to-r from-transparent via-secondary to-transparent" aria-hidden />
        <Wallet className="w-5 h-5" />
        <div className="text-left">
          <p className="text-[10px] uppercase tracking-[0.22em] opacity-90 font-bold">Gains · CHOPPay</p>
          <p className="text-xl font-extrabold">+ 7 225 GNF</p>
        </div>
      </motion.div>
      <p className="text-[11px] text-muted-foreground flex items-center gap-1">
        <Flag className="w-3 h-3" /> Course terminée
      </p>
    </div>
  );
}

function HeatmapScene({ animated }: { animated: boolean }) {
  const blobs = [
    { x: "20%", y: "30%", s: 90,  c: "hsl(var(--secondary))" },
    { x: "60%", y: "55%", s: 110, c: "hsl(var(--primary))" },
    { x: "75%", y: "20%", s: 70,  c: "hsl(var(--destructive))" },
  ];
  return (
    <div className="relative w-full h-full rounded-3xl overflow-hidden card-warm">
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />
      <div className="absolute inset-0 opacity-40"
        style={{
          backgroundImage:
            "linear-gradient(hsl(var(--border)) 1px, transparent 1px), linear-gradient(90deg, hsl(var(--border)) 1px, transparent 1px)",
          backgroundSize: "28px 28px",
        }} />
      {blobs.map((b, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, scale: 0.6 }}
          animate={animated ? { opacity: [0.4, 0.75, 0.4], scale: [1, 1.15, 1] } : { opacity: 0.6, scale: 1 }}
          transition={{ duration: 2.4, repeat: Infinity, delay: i * 0.3 }}
          className="absolute rounded-full blur-2xl"
          style={{ left: b.x, top: b.y, width: b.s, height: b.s, background: b.c }}
        />
      ))}
      <div className="absolute left-3 bottom-3 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-secondary/95 text-secondary-foreground text-xs font-bold shadow-card">
        <Flame className="w-4 h-4" /> Forte demande à Kaloum
      </div>
    </div>
  );
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
      <p className="text-lg font-extrabold tracking-tight">CHOP CHOP · Chauffeur</p>
      <p className="text-sm opacity-90 mt-1">Conduisez mieux. Gagnez mieux.</p>
    </div>
  );
}

function Scene({ scene, animated }: { scene: SceneKey; animated: boolean }) {
  switch (scene) {
    case "online":   return <OnlineScene animated={animated} />;
    case "accept":   return <AcceptScene animated={animated} />;
    case "pickup":   return <PickupScene animated={animated} />;
    case "complete": return <CompleteScene animated={animated} />;
    case "heatmap":  return <HeatmapScene animated={animated} />;
    case "final":    return <FinalScene />;
  }
}

export function DriverOnboarding({ onDone }: Props) {
  const [index, setIndex] = useState(0);
  const { low } = useLowDataMode();
  const animated = !low;
  const scene = SCENES[index];
  const isLast = index === SCENES.length - 1;

  const next = () => {
    if (isLast) onDone();
    else setIndex((i) => i + 1);
  };
  const prev = () => setIndex((i) => Math.max(0, i - 1));

  return (
    <OnboardingShell
      ariaLabel="Bienvenue chauffeur CHOP CHOP"
      steps={SCENES.length}
      index={index}
      isLast={isLast}
      sceneKey={scene.key}
      scene={<Scene scene={scene.key} animated={animated} />}
      title={scene.title}
      caption={scene.caption}
      primaryLabel="Entrer dans CHOP CHOP"
      footerCaption="CHOP CHOP · Chauffeur · Conakry"
      onNext={next}
      onPrev={prev}
      onClose={onDone}
    />
  );
}

export const DRIVER_ONBOARDING_DONE_KEY = "cc_driver_onboarding_done";
export const DRIVER_ONBOARDING_REPLAY_EVENT = "cc:replay-driver-onboarding";
