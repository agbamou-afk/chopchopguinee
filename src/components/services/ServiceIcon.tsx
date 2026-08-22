import type { ComponentType } from "react";
import {
  ENTRY_CHIP_CLASS,
  ENTRY_GLYPH_CLASS,
  SERVICE_CHIP_CLASS,
  SERVICE_GLYPH_CLASS,
  UTILITY_STROKE_WIDTH,
  getServiceIconAsset,
  getServiceIconTuning,
  type IconFamily,
} from "@/lib/services/serviceIcons";

export type GlyphComponent = ComponentType<{ className?: string; strokeWidth?: number | string }>;

interface ServiceIconProps {
  /** Canonical service/action id — drives asset + optical tuning lookup. */
  id: string;
  /** Family A = transactional product, Family B = entry/utility action. */
  family: IconFamily;
  /** Lucide (or Lucide-like) glyph. Required for Family B and for Family-A placeholders. */
  Glyph?: GlyphComponent;
  /** Optional halo override for Family A (home surfaces use per-service halos). */
  chipClassName?: string;
  /** Image sizing/animation classes. Defaults to the standard `w-11 h-11` badge. */
  imgClassName?: string;

}

/**
 * Canonical renderer for the two CHOPCHOP icon families. Every customer
 * discovery surface must go through this component so badge size, ring,
 * background, optical scale and a11y stay identical everywhere.
 *
 * The chip is always decorative: the accessible name lives on the parent
 * button's `aria-label`.
 */
export function ServiceIcon({ id, family, Glyph, chipClassName, imgClassName }: ServiceIconProps) {
  if (family === "entry") {
    return (
      <div className={chipClassName ?? ENTRY_CHIP_CLASS} aria-hidden>
        {Glyph ? <Glyph className={ENTRY_GLYPH_CLASS} strokeWidth={UTILITY_STROKE_WIDTH} /> : null}
      </div>
    );
  }

  const asset = getServiceIconAsset(id);
  const t = getServiceIconTuning(id);

  return (
    <div className={chipClassName ?? SERVICE_CHIP_CLASS} aria-hidden>
      {asset ? (
        <img
          src={asset}
          alt=""
          aria-hidden
          loading="lazy"
          width={1024}
          height={1024}
          className={`${imgClassName ?? "w-11 h-11"} object-contain`}
          style={{ transform: `translate(${t.x}px, ${t.y}px) scale(${t.scale})` }}
        />
      ) : Glyph ? (
        // PASS 1: branded art missing for this service — Family-A chip with a
        // clearly marked glyph placeholder. Never borrow another service's art.
        <Glyph className={SERVICE_GLYPH_CLASS} strokeWidth={UTILITY_STROKE_WIDTH} />
      ) : null}
    </div>
  );
}
