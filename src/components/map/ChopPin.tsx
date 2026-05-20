import React from "react";
import { cn } from "@/lib/utils";
import {
  TONE_HSL, pinIcon, pinTone,
  type ChopPinKind, type ChopPinTone,
} from "./chopPinTypes";

export type ChopPinVariant = "map" | "inline" | "card" | "timeline" | "receipt" | "compact";

const SIZE_PX: Record<ChopPinVariant, number> = {
  map: 38, inline: 24, card: 28, timeline: 20, receipt: 22, compact: 18,
};

interface Props {
  kind: ChopPinKind;
  variant?: ChopPinVariant;
  /** Render as a teardrop map pin (anchored at bottom). Default true for `map`. */
  pin?: boolean;
  /** Soft pulse halo for active surfaces (use sparingly). */
  pulse?: boolean;
  selected?: boolean;
  /** Aria label for meaningful pins. Set "" or omit for decorative. */
  label?: string;
  onClick?: () => void;
  className?: string;
  /** Override tone (rare — use only for status overlays on category pins). */
  toneOverride?: ChopPinTone;
}

/**
 * Conakry Contemporary unified pin.
 * - Universal teardrop silhouette (or flat circle for inline variants)
 * - White inner field for legibility on warm map base
 * - Single Lucide glyph at 1.75 stroke
 * - Universal color semantics from chopPinTypes
 */
export function ChopPin({
  kind,
  variant = "map",
  pin,
  pulse,
  selected,
  label,
  onClick,
  className,
  toneOverride,
}: Props) {
  const size = SIZE_PX[variant];
  const tone = toneOverride ?? pinTone(kind);
  const color = TONE_HSL[tone];
  const Icon = pinIcon(kind);
  const isPin = pin ?? variant === "map";
  const interactive = !!onClick;

  const inner = (
    <span
      aria-hidden
      className={cn(
        "relative inline-flex items-center justify-center",
        isPin ? "rounded-full" : "rounded-full",
      )}
      style={{
        width: size,
        height: size,
        backgroundColor: color,
        boxShadow: isPin
          ? "0 0 0 1.5px hsl(var(--background)) inset, 0 6px 12px -6px hsl(30 25% 12% / 0.45)"
          : "0 0 0 1px hsl(var(--background)) inset",
      }}
    >
      <span
        className="flex items-center justify-center rounded-full bg-white"
        style={{ width: size * 0.66, height: size * 0.66 }}
      >
        <Icon
          width={size * 0.42}
          height={size * 0.42}
          strokeWidth={1.75}
          style={{ color }}
          aria-hidden
        />
      </span>
    </span>
  );

  const content = isPin ? (
    <span
      className="relative inline-block"
      style={{ width: size, height: size + Math.round(size * 0.18) }}
    >
      {pulse && (
        <span
          className="absolute inset-x-0 top-0 rounded-full animate-ping opacity-30"
          style={{ height: size, backgroundColor: color, animationDuration: "2.4s" }}
          aria-hidden
        />
      )}
      {inner}
      {/* teardrop tail */}
      <span
        aria-hidden
        className="absolute left-1/2 -translate-x-1/2"
        style={{
          bottom: 0,
          width: 0,
          height: 0,
          borderLeft: `${size * 0.18}px solid transparent`,
          borderRight: `${size * 0.18}px solid transparent`,
          borderTop: `${size * 0.22}px solid ${color}`,
          filter: "drop-shadow(0 2px 2px hsl(30 25% 12% / 0.25))",
        }}
      />
    </span>
  ) : (
    <span className="relative inline-flex">
      {pulse && (
        <span
          className="absolute inset-0 rounded-full animate-ping opacity-30"
          style={{ backgroundColor: color, animationDuration: "2.4s" }}
          aria-hidden
        />
      )}
      {inner}
    </span>
  );

  if (interactive) {
    return (
      <button
        type="button"
        onClick={onClick}
        aria-label={label ?? undefined}
        className={cn(
          "inline-flex items-end justify-center transition-transform duration-200",
          selected && "scale-110",
          className,
        )}
      >
        {content}
      </button>
    );
  }

  return (
    <span
      role={label ? "img" : undefined}
      aria-label={label || undefined}
      aria-hidden={label ? undefined : true}
      className={cn(
        "inline-flex items-end justify-center",
        selected && "scale-110",
        className,
      )}
    >
      {content}
    </span>
  );
}
