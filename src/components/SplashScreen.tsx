import { motion } from "framer-motion";
import { useState } from "react";
import logo from "@/assets/logo.png";
import skyline from "@/assets/splash-skyline.png";

interface SplashScreenProps {
  onFinish?: () => void;
}

export function SplashScreen({ onFinish }: SplashScreenProps) {
  const [introDone, setIntroDone] = useState(false);
  const words = [
    { text: "Tout.", color: "text-destructive" },
    { text: "Partout.", color: "text-secondary" },
    { text: "Pour Tous.", color: "text-primary" },
  ];
  const introTotal = 0.6 + words.length * 0.45 + 0.4;
  return (
    <motion.div
      initial={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.8 }}
      className="fixed inset-0 z-[100] flex flex-col items-center justify-between py-16 px-6 overflow-hidden"
      style={{
        background:
          "radial-gradient(120% 80% at 50% 0%, hsl(38 60% 95%) 0%, hsl(36 40% 92%) 45%, hsl(36 30% 88%) 100%)",
      }}
    >
      {/* Atmospheric warm haze */}
      <div
        className="pointer-events-none absolute inset-0"
        aria-hidden
        style={{
          background:
            "radial-gradient(60% 40% at 20% 20%, hsl(var(--secondary) / 0.10), transparent 70%), radial-gradient(50% 35% at 85% 30%, hsl(var(--primary) / 0.08), transparent 70%)",
        }}
      />
      {/* Subtle Conakry silhouette band */}
      <svg
        className="pointer-events-none absolute inset-x-0 bottom-24 w-full h-24 opacity-[0.10]"
        viewBox="0 0 400 80"
        preserveAspectRatio="none"
        aria-hidden
      >
        <path
          d="M0,80 L0,55 L18,55 L22,42 L26,55 L48,55 L48,38 L62,38 L62,55 L78,55 L82,28 L86,55 L110,55 L110,46 L128,46 L128,32 L134,32 L134,46 L150,46 L150,55 L172,55 L176,40 L180,55 L210,55 L210,34 L228,34 L228,55 L252,55 L256,22 L260,55 L286,55 L286,44 L304,44 L304,55 L330,55 L334,36 L338,55 L362,55 L362,48 L382,48 L382,55 L400,55 L400,80 Z"
          fill="hsl(var(--foreground))"
        />
      </svg>
      {/* Decorative palm at edge */}
      <img
        src={skyline}
        alt=""
        aria-hidden
        className="pointer-events-none absolute -right-10 bottom-16 w-72 opacity-25 select-none"
      />
      {/* Spacer */}
      <div className="flex-1 relative" />

      {/* Center logo */}
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 1.6, ease: "easeOut" }}
        className="flex flex-col items-center relative"
      >
        <motion.img
          src={logo}
          alt="Chop Chop"
          className="w-56 h-56 object-contain mix-blend-multiply dark:mix-blend-screen"
          initial={{ y: 10 }}
          animate={{ y: 0 }}
          transition={{ duration: 1.2, ease: "easeOut" }}
        />

        {/* Loading dots */}
        <div className="flex items-center gap-2 mt-8">
          {[
            "bg-destructive",
            "bg-secondary",
            "bg-primary",
          ].map((color, i) => (
            <motion.span
              key={i}
              className={`w-2.5 h-2.5 rounded-full ${color}`}
              animate={{ opacity: [0.3, 1, 0.3], scale: [0.8, 1.2, 0.8] }}
              transition={{
                duration: 2.4,
                repeat: Infinity,
                delay: i * 0.4,
              }}
            />
          ))}
        </div>

        <p className="mt-4 text-xs tracking-[0.3em] text-muted-foreground uppercase">
          Chargement...
        </p>
      </motion.div>

      {/* Spacer */}
      <div className="flex-1 relative" />

      {/* Bottom slogan */}
      <div className="w-full relative overflow-hidden">
        {!introDone ? (
          <motion.div
            className="flex items-center justify-center gap-2 text-base sm:text-lg font-extrabold uppercase tracking-wide"
            onAnimationComplete={() => setTimeout(() => setIntroDone(true), introTotal * 2000)}
          >
            {words.map((word, i) => (
              <motion.span
                key={word.text}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.9, ease: "easeOut", delay: 1.2 + i * 0.9 }}
                className={word.color}
              >
                {word.text}
              </motion.span>
            ))}
          </motion.div>
        ) : (
          <div className="flex whitespace-nowrap">
            <motion.div
              className="flex shrink-0 gap-2 text-base sm:text-lg font-extrabold uppercase tracking-wide pr-2"
              animate={{ x: ["0%", "-100%"] }}
              transition={{ duration: 24, ease: "linear", repeat: Infinity }}
            >
              {Array.from({ length: 6 }).map((_, k) => (
                <span key={k} className="flex gap-2 pr-6">
                  {words.map((w) => (
                    <span key={w.text} className={w.color}>{w.text}</span>
                  ))}
                </span>
              ))}
            </motion.div>
          </div>
        )}
      </div>
    </motion.div>
  );
}
