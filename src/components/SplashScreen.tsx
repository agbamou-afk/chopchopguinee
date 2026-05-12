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
      className="fixed inset-0 z-[100] bg-background flex flex-col items-center justify-between py-16 px-6"
      onAnimationComplete={() => {
        // outer trigger handled by parent timer
      }}
    >
      {/* Spacer */}
      <div className="flex-1" />

      {/* Center logo */}
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.8, ease: "easeOut" }}
        className="flex flex-col items-center"
      >
        <motion.img
          src={logo}
          alt="Chop Chop"
          className="w-56 h-56 object-contain"
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
      <div className="flex-1" />

      {/* Bottom slogan */}
      <div className="w-full overflow-hidden">
        <motion.div
          initial={{ x: "100%" }}
          animate={{ x: 0 }}
          transition={{ duration: 1, ease: "easeOut", delay: 0.3 }}
          className="flex items-center justify-center gap-2 text-base sm:text-lg font-extrabold uppercase tracking-wide"
        >
          <span className="text-destructive">Tout.</span>
          <span className="text-secondary">Partout.</span>
          <span className="text-primary">Pour Tous.</span>
        </motion.div>
      </div>
    </motion.div>
  );
}
