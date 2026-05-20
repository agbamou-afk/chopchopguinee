import React from 'react';
import { type MarkerVariant, type MarkerState } from '@/lib/maps/markerIcons';
import { ChopPin } from './ChopPin';
import { kindFromLegacyVariant } from './chopPinTypes';
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
  // Legacy MapMarker now delegates to the unified ChopPin system so every
  // map marker speaks the same Conakry Contemporary pin language.
  const kind = kindFromLegacyVariant(variant, state);
  return (
    <span
      className={cn(
        'inline-flex items-end justify-center transition-transform duration-200',
        selected && 'scale-110',
      )}
      style={{ width: size }}
    >
      <ChopPin
        kind={kind}
        variant="map"
        pin
        pulse={pulse}
        selected={selected}
        label={label ?? variant}
        onClick={onClick}
      />
    </span>
  );
}