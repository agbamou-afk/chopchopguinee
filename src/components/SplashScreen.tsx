import { motion } from "framer-motion";
import logo from "@/assets/logo.png";

interface SplashScreenProps {
  onFinish?: () => void;
}

export function SplashScreen({ onFinish }: SplashScreenProps) {
  return (
    <motion.div
      initial={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.4 }}
      className="fixed inset-0 z-[100] bg-background flex flex-col items-center justify-between py-16 px-6 overflow-hidden"
    >
      {/* Soft radial glow to blend logo into background */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse at center, hsl(var(--primary) / 0.12) 0%, hsl(var(--background) / 0) 60%)",
        }}
      />

      {/* Spacer */}
      <div className="flex-1 relative" />

      {/* Center logo */}
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.8, ease: "easeOut" }}
        className="flex flex-col items-center relative"
      >
        <motion.img
          src={logo}
          alt="Chop Chop"
          className="w-56 h-56 object-contain mix-blend-multiply dark:mix-blend-screen drop-shadow-[0_8px_30px_hsl(var(--primary)/0.25)]"
          initial={{ y: 10 }}
          animate={{ y: 0 }}
          transition={{ duration: 0.6, ease: "easeOut" }}
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
                duration: 1.2,
                repeat: Infinity,
                delay: i * 0.2,
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
      <div className="w-full relative">
        <div className="flex items-center justify-center gap-2 text-base sm:text-lg font-extrabold uppercase tracking-wide">
          {[
            { text: "Tout.", color: "text-destructive" },
            { text: "Partout.", color: "text-secondary" },
            { text: "Pour Tous.", color: "text-primary" },
          ].map((word, i) => (
            <motion.span
              key={word.text}
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{
                duration: 0.45,
                ease: "easeOut",
                delay: 0.6 + i * 0.45,
              }}
              className={word.color}
            >
              {word.text}
            </motion.span>
          ))}
        </div>
      </div>
    </motion.div>
  );
}
