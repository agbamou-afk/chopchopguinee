import { useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";

interface Props {
  open: boolean;
  onClose: () => void;
}

/**
 * CHOPCHOP "under construction" announcement.
 *
 * Full-screen-card modal, mobile-first, matching the onboarding storybook
 * visual family. Background is a strict 3-tone illustration (deep green /
 * warm cream / sunset gold) rendered as inline SVG so the palette stays
 * locked and scales crisply on every viewport.
 */
export function UnderConstructionModal({ open, onClose }: Props) {
  // Lock body scroll while open.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, [open]);

  // Escape to close.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          key="uc-modal"
          role="dialog"
          aria-modal="true"
          aria-labelledby="uc-title"
          className="fixed inset-0 z-[120] flex items-center justify-center bg-black/55 backdrop-blur-sm"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.25 }}
          style={{
            paddingTop: "env(safe-area-inset-top)",
            paddingBottom: "env(safe-area-inset-bottom)",
            paddingLeft: "env(safe-area-inset-left)",
            paddingRight: "env(safe-area-inset-right)",
          }}
          onClick={onClose}
        >
          <motion.div
            initial={{ opacity: 0, y: 16, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 12, scale: 0.98 }}
            transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
            onClick={(e) => e.stopPropagation()}
            className="relative w-full max-w-md mx-4 overflow-hidden rounded-3xl shadow-2xl"
            style={{ backgroundColor: "#0f3d2e" }}
          >
            {/* Background illustration — strict 3-tone palette */}
            <UnderConstructionBackground />

            {/* Legibility gradient overlay */}
            <div
              aria-hidden
              className="absolute inset-0 pointer-events-none"
              style={{
                background:
                  "linear-gradient(180deg, rgba(15,61,46,0.05) 0%, rgba(15,61,46,0.35) 55%, rgba(15,61,46,0.85) 100%)",
              }}
            />

            {/* Close button */}
            <button
              type="button"
              onClick={onClose}
              aria-label="Fermer"
              className="absolute top-3 right-3 z-10 inline-flex h-9 w-9 items-center justify-center rounded-full bg-black/30 text-[#f7ead0] hover:bg-black/50 transition-colors"
            >
              <X className="h-4 w-4" />
            </button>

            {/* Content */}
            <div className="relative z-[1] flex flex-col min-h-[560px] px-6 pt-5 pb-7">
              {/* Badge */}
              <div className="self-start inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#f7ead0]/90 text-[#0f3d2e] text-[11px] font-semibold tracking-wide uppercase">
                <span className="h-1.5 w-1.5 rounded-full bg-[#e8a23a]" />
                Bêta
              </div>

              {/* Spacer pushes copy to bottom over the dark gradient */}
              <div className="flex-1" />

              <div className="space-y-3 text-[#f7ead0]">
                <h2
                  id="uc-title"
                  className="text-[26px] leading-tight font-bold tracking-tight"
                >
                  CHOPCHOP arrive bientôt
                </h2>
                <p className="text-[15px] leading-relaxed text-[#f7ead0]/90">
                  Nous finalisons encore l'application. Vous pouvez déjà la
                  parcourir et découvrir l'expérience pendant que nous préparons
                  le lancement.
                </p>

                {/* Recruitment callouts — light pills, Guinean pilot energy */}
                <div className="mt-4 space-y-2">
                  <div className="rounded-xl bg-[#f7ead0]/8 border border-[#f7ead0]/12 px-3.5 py-2.5">
                    <p className="text-[12.5px] leading-snug text-[#f7ead0]/90">
                      Vous êtes chauffeur ou coursier ?{" "}
                      <span className="font-semibold text-[#e8a23a]">
                        CHOPCHOP recrute ses premiers partenaires.
                      </span>
                    </p>
                  </div>
                  <div className="rounded-xl bg-[#f7ead0]/8 border border-[#f7ead0]/12 px-3.5 py-2.5">
                    <p className="text-[12.5px] leading-snug text-[#f7ead0]/90">
                      Vous êtes marchand ?{" "}
                      <span className="font-semibold text-[#e8a23a]">
                        Inscrivez votre boutique dès maintenant pour préparer
                        votre catalogue et toucher plus de clients.
                      </span>
                    </p>
                  </div>
                </div>

                <p className="text-[11.5px] text-[#f7ead0]/60 leading-relaxed">
                  Les premiers partenaires nous aideront à construire le réseau
                  CHOPCHOP à Conakry.
                </p>
              </div>

              <Button
                onClick={onClose}
                className="mt-6 w-full h-12 rounded-2xl bg-[#e8a23a] hover:bg-[#d99325] text-[#0f3d2e] font-semibold text-base shadow-lg"
              >
                Continuer
              </Button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/**
 * Strict 3-tone illustration: deep green (#0f3d2e), warm cream (#f7ead0),
 * sunset gold (#e8a23a). Tropical sunset silhouette with a subtle ticking
 * clock motif (hour hand rotates slowly).
 */
function UnderConstructionBackground() {
  return (
    <div className="absolute inset-0 overflow-hidden" aria-hidden>
      <svg
        viewBox="0 0 400 600"
        preserveAspectRatio="xMidYMid slice"
        className="absolute inset-0 h-full w-full"
      >
        {/* Sky / cream backdrop */}
        <rect width="400" height="600" fill="#f7ead0" />

        {/* Sun — sunset gold */}
        <circle cx="200" cy="240" r="92" fill="#e8a23a" />

        {/* Faint sun glow rings (still gold, just lower opacity) */}
        <circle cx="200" cy="240" r="120" fill="#e8a23a" opacity="0.22" />
        <circle cx="200" cy="240" r="150" fill="#e8a23a" opacity="0.12" />

        {/* Horizon water — deep green band */}
        <rect x="0" y="330" width="400" height="40" fill="#0f3d2e" opacity="0.15" />

        {/* Clock face sitting over the sun — cream disc */}
        <g>
          <circle cx="200" cy="240" r="54" fill="#f7ead0" />
          <circle
            cx="200"
            cy="240"
            r="54"
            fill="none"
            stroke="#0f3d2e"
            strokeWidth="3"
          />
          {/* Hour ticks */}
          {Array.from({ length: 12 }).map((_, i) => {
            const a = (i * Math.PI) / 6;
            const x1 = 200 + Math.sin(a) * 46;
            const y1 = 240 - Math.cos(a) * 46;
            const x2 = 200 + Math.sin(a) * 52;
            const y2 = 240 - Math.cos(a) * 52;
            return (
              <line
                key={i}
                x1={x1}
                y1={y1}
                x2={x2}
                y2={y2}
                stroke="#0f3d2e"
                strokeWidth={i % 3 === 0 ? 3 : 1.5}
                strokeLinecap="round"
              />
            );
          })}
          {/* Minute hand (static, pointing up-right) */}
          <line
            x1="200"
            y1="240"
            x2="228"
            y2="214"
            stroke="#0f3d2e"
            strokeWidth="3"
            strokeLinecap="round"
          />
          {/* Hour hand — slow ticking rotation around exact clock center
              (200, 240). Uses SVG animateTransform so the pivot is part of
              the rotate command itself and isn't affected by CSS
              transform-box quirks across browsers. */}
          <g>
            <line
              x1="200"
              y1="240"
              x2="200"
              y2="212"
              stroke="#0f3d2e"
              strokeWidth="4"
              strokeLinecap="round"
            >
              <animateTransform
                attributeName="transform"
                attributeType="XML"
                type="rotate"
                from="0 200 240"
                to="360 200 240"
                dur="60s"
                repeatCount="indefinite"
              />
            </line>
          </g>
          {/* Center pin — sunset gold */}
          <circle cx="200" cy="240" r="4" fill="#e8a23a" />
        </g>

        {/* Palm tree silhouettes — deep green only */}
        <g fill="#0f3d2e">
          {/* Left palm */}
          <path d="M70 600 C 72 520, 76 460, 78 410 L 86 410 C 88 470, 92 530, 94 600 Z" />
          <path d="M82 410 C 50 395, 30 405, 18 420 C 38 412, 60 412, 82 418 Z" />
          <path d="M82 410 C 110 390, 132 395, 150 410 C 128 405, 104 408, 84 418 Z" />
          <path d="M82 410 C 70 380, 56 360, 40 348 C 60 368, 72 388, 84 414 Z" />
          <path d="M82 410 C 96 380, 112 362, 130 350 C 110 372, 96 392, 84 414 Z" />
          {/* Right palm — smaller, further */}
          <path d="M330 600 C 332 540, 335 490, 337 450 L 343 450 C 345 500, 348 550, 350 600 Z" />
          <path d="M340 450 C 318 440, 302 446, 290 458 C 308 450, 324 450, 340 456 Z" />
          <path d="M340 450 C 362 438, 380 444, 392 458 C 374 450, 356 450, 340 456 Z" />
          <path d="M340 450 C 332 426, 322 410, 308 400 C 324 418, 334 434, 342 454 Z" />
          <path d="M340 450 C 350 426, 362 412, 376 402 C 360 420, 350 436, 342 454 Z" />
        </g>

        {/* Ground band */}
        <rect x="0" y="560" width="400" height="40" fill="#0f3d2e" />
      </svg>
    </div>
  );
}