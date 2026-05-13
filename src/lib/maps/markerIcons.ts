export type MarkerVariant =
  | 'moto' | 'toktok' | 'food' | 'livraison' | 'wallet' | 'marche'
  | 'marketplace_pickup' | 'user_pickup' | 'pickup' | 'dropoff';

export type MarkerState = 'online' | 'offline' | 'busy' | 'unavailable';

export function markerColor(variant: MarkerVariant, state: MarkerState = 'online'): string {
  if (state === 'offline') return 'hsl(0 0% 60%)';
  if (state === 'unavailable') return 'hsl(0 0% 45%)';
  if (state === 'busy') return 'hsl(38 95% 52%)';
  switch (variant) {
    case 'moto':    return 'hsl(138 64% 39%)';
    case 'toktok':  return 'hsl(45 90% 55%)';
    case 'food':    return 'hsl(8 78% 55%)';
    case 'livraison': return 'hsl(28 85% 52%)';
    case 'wallet':  return 'hsl(38 95% 52%)';
    case 'marche':  return 'hsl(142 55% 38%)';
    case 'marketplace_pickup': return 'hsl(170 55% 40%)';
    case 'user_pickup':        return 'hsl(220 70% 55%)';
    case 'pickup':  return 'hsl(138 64% 39%)';
    case 'dropoff': return 'hsl(2 75% 56%)';
  }
}

export const variantGlyph: Record<MarkerVariant, string> = {
  moto:   'M5 17a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm14 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM6 14h6l3-6h3l1 3',
  toktok: 'M3 13h13v4H3zM16 9h3l2 4v4h-5z M6 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm12 0a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z',
  food:   'M4 4v8a4 4 0 0 0 4 4v4M14 4c0 4 6 4 6 0v8a4 4 0 0 1-4 4v4',
  livraison: 'M3 7h11v8H3zM14 10h4l3 3v2h-7zM6 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm11 0a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z',
  wallet: 'M3 7h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7zM3 7l3-3h12v3 M16 13h2',
  marche: 'M4 7h16l-1 11H5L4 7zM8 7V5a4 4 0 0 1 8 0v2',
  marketplace_pickup: 'M4 7h16l-1 11H5L4 7zM8 7V5a4 4 0 0 1 8 0v2 M9 13l2 2 4-4',
  user_pickup: 'M12 2a4 4 0 1 1 0 8 4 4 0 0 1 0-8zM4 21a8 8 0 0 1 16 0',
  pickup: 'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9a2 2 0 1 1 0-4 2 2 0 0 1 0 4z',
  dropoff:'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9a2 2 0 1 1 0-4 2 2 0 0 1 0 4z',
};