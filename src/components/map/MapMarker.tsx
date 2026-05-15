import React from 'react';
import { markerColor, variantGlyph, type MarkerVariant, type MarkerState } from '@/lib/maps/markerIcons';
import { cn } from '@/lib/utils';

interface Props {
  variant: MarkerVariant;
  state?: MarkerState;
  rotation?: number;
  pulse?: boolean;
  selected?: boolean;
  size?: number;
  label?: string;
  onClick?: () => void;
}

export function MapMarker({
  variant, state = 'online', rotation = 0, pulse, selected, size = 36, label, onClick,
}: Props) {
  const color = markerColor(variant, state);
  const isPin = variant === 'pickup' || variant === 'dropoff';
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label ?? variant}
      className={cn(
        'relative flex items-center justify-center transition-transform duration-200',
        selected && 'scale-110',
      )}
      style={{ width: size, height: size }}
    >
      {pulse && (
        <span
          className="absolute inset-0 rounded-full animate-ping opacity-40"
          style={{ backgroundColor: color }}
        />
      )}
      <span
        className={cn(
          'relative flex items-center justify-center rounded-full shadow-island ring-2 ring-white',
          isPin && 'rounded-b-full',
        )}
        style={{
          width: size,
          height: size,
          backgroundColor: color,
          transform: isPin ? undefined : `rotate(${rotation}deg)`,
          boxShadow:
            '0 0 0 1px hsl(var(--secondary) / 0.45), 0 0 0 4px hsl(var(--background) / 0.55), 0 8px 18px -8px hsl(30 25% 12% / 0.40)',
        }}
      >
        <svg
          viewBox="0 0 24 24"
          width={size * 0.55}
          height={size * 0.55}
          fill="none"
          stroke="white"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d={variantGlyph[variant]} />
        </svg>
      </span>
    </button>
  );
}