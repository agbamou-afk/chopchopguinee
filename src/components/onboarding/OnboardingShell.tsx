import { ReactNode, useEffect } from "react";
import { motion, AnimatePresence, PanInfo } from "framer-motion";
import { ChevronLeft, ChevronRight, X } from "lucide-react";
import { useLowDataMode } from "@/hooks/useLowDataMode";

interface Props {
  ariaLabel: string;
  steps: number;
  index: number;
  isLast: boolean;
  sceneKey: string;
  scene: ReactNode;
  title: string;
  caption: string;
  primaryLabel: string;
  secondary?: { label: string; onClick: () => void };
  footerCaption: string;
  onNext: () => void;
  onPrev: () => void;
  onClose: () => void;
}

/**
 * OnboardingShell — Conakry Contemporary unified onboarding shell.
 * Locks structure (header, illustration frame, copy block, footer)
 * across client + chauffeur onboarding. Urban Flow motion language.
 */
export function OnboardingShell({
  ariaLabel, steps, index, isLast, sceneKey, scene, title, caption,
  primaryLabel, secondary, footerCaption, onNext, onPrev, onClose,
}: Props) {
  const { low } = useLowDataMode();

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, []);

  const onDragEnd = (_: unknown, info: PanInfo) => {
    if (info.offset.x < -60) onNext();
    else if (info.offset.x > 60 && index > 0) onPrev();
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.25 }}
      className="fixed inset-0 z-[80] bg-app-conakry flex flex-col touch-none"
      role="dialog"
      aria-modal="true"
      aria-label={ariaLabel}
    >
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[2px] kente-stripe z-10" aria-hidden />

      {/* Header — reserved height, X only on final slide */}
      <div className="h-12 flex items-center justify-end px-4 pt-[max(0.5rem,env(safe-area-inset-top))]">
        {isLast ? (
          <button
            onClick={onClose}
            className="inline-flex items-center justify-center w-10 h-10 rounded-full text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
            aria-label="Fermer"
          >
            <X className="w-5 h-5" />
          </button>
        ) : (
          <span className="w-10 h-10" aria-hidden />
        )}
      </div>

      {/* Body — fixed illustration frame + copy block */}
      <div className="flex-1 flex flex-col justify-center max-w-md w-full mx-auto px-5">
        <AnimatePresence mode="wait">
          <motion.div
            key={sceneKey}
            initial={{ opacity: 0, x: low ? 0 : 24 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: low ? 0 : -24 }}
            transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
            drag="x"
            dragConstraints={{ left: 0, right: 0 }}
            dragElastic={0.18}
            onDragEnd={onDragEnd}
            className="space-y-5"
          >
            <div className="h-56 w-full">{scene}</div>
            <div className="text-center min-h-[88px] px-2">
              <p className="text-[11px] uppercase tracking-[0.22em] font-bold text-primary">
                {title}
              </p>
              <p className="text-[17px] leading-snug font-extrabold text-foreground mt-2 max-w-[22ch] mx-auto">
                {caption}
              </p>
            </div>
          </motion.div>
        </AnimatePresence>
      </div>

      {/* Footer — fixed structure, anchored controls */}
      <div className="px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-2 max-w-md w-full mx-auto">
        <div className="flex items-center justify-center gap-1.5 mb-4 h-1.5">
          {Array.from({ length: steps }).map((_, i) => (
            <span
              key={i}
              className={`h-1.5 rounded-full transition-all duration-300 ease-out ${
                i === index ? "w-7 bg-gradient-to-r from-primary to-secondary" : "w-1.5 bg-border"
              }`}
            />
          ))}
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={onPrev}
            disabled={index === 0}
            className="inline-flex items-center justify-center w-14 h-14 rounded-2xl border border-border bg-card text-foreground disabled:opacity-30 disabled:pointer-events-none active:scale-[0.97] transition shrink-0"
            aria-label="Précédent"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <button
            onClick={onNext}
            className="flex-1 inline-flex items-center justify-center gap-2 h-14 rounded-2xl gradient-cta text-primary-foreground font-bold text-base hover:opacity-95 active:scale-[0.985] transition"
          >
            {isLast ? primaryLabel : (<>Suivant <ChevronRight className="w-5 h-5" /></>)}
          </button>
        </div>

        <div className="h-10 mt-2 flex items-center justify-center">
          {isLast && secondary ? (
            <button
              onClick={secondary.onClick}
              className="text-sm font-semibold text-primary hover:opacity-80 transition"
            >
              {secondary.label}
            </button>
          ) : null}
        </div>

        <p className="text-center text-[10px] uppercase tracking-[0.22em] text-muted-foreground/80">
          {footerCaption}
        </p>
      </div>
    </motion.div>
  );
}