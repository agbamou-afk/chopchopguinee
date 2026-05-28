import { ReactNode, useEffect } from "react";
import { motion, AnimatePresence, PanInfo } from "framer-motion";
import { ChevronLeft, ChevronRight, X } from "lucide-react";
import { useLowDataMode } from "@/hooks/useLowDataMode";

export interface StorybookSlide {
  id: string;
  title: string;
  body: string;
  image: string;
  alt: string;
  /** Optional foreground composition (e.g. ecosystem icon cluster). */
  overlay?: ReactNode;
}

interface Props {
  ariaLabel: string;
  slides: StorybookSlide[];
  index: number;
  primaryLabel: string;
  skipLabel?: string;
  footerCaption: string;
  onNext: () => void;
  onPrev: () => void;
  onSkip: () => void;
}

/**
 * OnboardingStorybook — Conakry Contemporary full-bleed storybook shell.
 * Full-screen illustration backdrop, floating controls, immersive titles.
 * Used by both Client and Driver onboarding for a consistent storybook feel.
 */
export function OnboardingStorybook({
  ariaLabel, slides, index, primaryLabel, skipLabel = "Passer",
  footerCaption, onNext, onPrev, onSkip,
}: Props) {
  const { low } = useLowDataMode();
  const slide = slides[index];
  const isLast = index === slides.length - 1;

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
      className="fixed inset-0 z-[80] bg-app-conakry overflow-hidden touch-none"
      role="dialog"
      aria-modal="true"
      aria-label={ariaLabel}
    >
      {/* Full-bleed illustration stack */}
      <AnimatePresence mode="wait">
        <motion.div
          key={slide.id}
          initial={{ opacity: 0, scale: low ? 1 : 1.04 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
          drag="x"
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.18}
          onDragEnd={onDragEnd}
          className="absolute inset-0"
        >
          <img
            src={slide.image}
            alt={slide.alt}
            loading={index === 0 ? "eager" : "lazy"}
            width={1024}
            height={1536}
            className="absolute inset-0 w-full h-full object-cover"
          />
          {/* Cream wash + bottom gradient for legible overlay text in light + dark */}
          <div
            className="pointer-events-none absolute inset-0"
            aria-hidden
            style={{
              background:
                "linear-gradient(180deg, hsl(var(--background) / 0.18) 0%, hsl(var(--background) / 0) 26%, hsl(var(--background) / 0) 42%, hsl(var(--background) / 0.55) 62%, hsl(var(--background) / 0.9) 82%, hsl(var(--background) / 0.98) 100%)",
            }}
          />
          {slide.overlay ? (
            <div className="absolute inset-0 pointer-events-none">{slide.overlay}</div>
          ) : null}
        </motion.div>
      </AnimatePresence>

      {/* Kente top seam */}
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[2px] kente-stripe z-30" aria-hidden />

      {/* Skip — top-right floating */}
      <div className="absolute top-[max(0.75rem,env(safe-area-inset-top))] right-3 z-40">
        {!isLast ? (
          <button
            onClick={onSkip}
            className="inline-flex items-center h-8 px-3.5 rounded-full bg-card/65 backdrop-blur text-foreground/85 text-[11.5px] font-semibold border border-border/50 shadow-soft active:scale-95 transition"
            aria-label="Passer l'introduction"
          >
            {skipLabel}
          </button>
        ) : (
          <button
            onClick={onSkip}
            className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-card/85 backdrop-blur text-foreground border border-border/60 shadow-soft active:scale-95 transition"
            aria-label="Fermer"
          >
            <X className="w-5 h-5" />
          </button>
        )}
      </div>

      {/* Floating copy block — anchored ~ mid-bottom */}
      <div className="absolute inset-x-0 bottom-0 z-30 px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-6">
        <div className="max-w-md mx-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={`${slide.id}-copy`}
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
              className="text-center mb-5"
            >
              <p className="text-[11px] uppercase tracking-[0.24em] font-bold text-primary mb-2">
                {String(index + 1).padStart(2, "0")} · {slides.length.toString().padStart(2, "0")}
              </p>
              <h2 className="text-[26px] leading-[1.1] font-extrabold tracking-tight text-foreground max-w-[20ch] mx-auto">
                {slide.title}
              </h2>
              <p className="text-[14.5px] leading-snug text-muted-foreground mt-3 max-w-[34ch] mx-auto">
                {slide.body}
              </p>
            </motion.div>
          </AnimatePresence>

          {/* Progress dots */}
          <div className="flex items-center justify-center gap-1.5 mb-4 h-1.5" aria-hidden>
            {slides.map((_, i) => (
              <span
                key={i}
                className={`h-1.5 rounded-full transition-all duration-300 ease-out ${
                  i === index ? "w-7 bg-gradient-to-r from-primary to-secondary" : "w-1.5 bg-border"
                }`}
              />
            ))}
          </div>

          {/* Floating controls */}
          {isLast ? (
            <div className="flex items-center gap-3">
              <button
                onClick={onPrev}
                className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-card border border-border text-foreground shadow-card active:scale-95 transition shrink-0"
                aria-label="Précédent"
              >
                <ChevronLeft className="w-5 h-5" />
              </button>
              <button
                onClick={onNext}
                className="flex-1 inline-flex items-center justify-center h-14 rounded-full gradient-cta text-primary-foreground font-bold text-base shadow-wallet active:scale-[0.985] transition"
              >
                {primaryLabel}
              </button>
            </div>
          ) : (
            <div className="flex items-center justify-between">
              {index === 0 ? (
                <div className="w-14 h-14" aria-hidden />
              ) : (
                <button
                  onClick={onPrev}
                  className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-card/90 backdrop-blur border border-border text-foreground shadow-card active:scale-95 transition"
                  aria-label="Précédent"
                >
                  <ChevronLeft className="w-5 h-5" />
                </button>
              )}
              <button
                onClick={onNext}
                className="inline-flex items-center justify-center w-16 h-16 rounded-full gradient-cta text-primary-foreground shadow-wallet active:scale-95 transition"
                aria-label="Suivant"
              >
                <ChevronRight className="w-6 h-6" />
              </button>
            </div>
          )}

          <p className="text-center text-[10px] uppercase tracking-[0.24em] text-muted-foreground/80 mt-3">
            {footerCaption}
          </p>
        </div>
      </div>
    </motion.div>
  );
}