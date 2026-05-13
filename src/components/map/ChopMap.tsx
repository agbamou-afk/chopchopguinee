import React, { forwardRef, useImperativeHandle, useRef } from 'react';
import Map, { type MapRef, NavigationControl, type ViewState } from 'react-map-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { useMapConfig } from '@/lib/maps';
import { Skeleton } from '@/components/ui/skeleton';
import { Analytics } from '@/lib/analytics/AnalyticsService';
import { useLowDataMode } from '@/hooks/useLowDataMode';
export interface ChopMapHandle {
  getMap: () => MapRef | null;
  flyTo: (lng: number, lat: number, zoom?: number) => void;
  fitBounds: (bbox: [number, number, number, number], padding?: number) => void;
}
interface Props {
  initialView?: Partial<ViewState>;
  className?: string;
  children?: React.ReactNode;
  interactive?: boolean;
  onLoad?: () => void;
}
export const ChopMap = forwardRef<ChopMapHandle, Props>(function ChopMap(
  { initialView, className, children, interactive = true, onLoad }, ref,
) {
  const { config, error } = useMapConfig();
  const mapRef = useRef<MapRef>(null);
  const loadedRef = useRef(false);
  const { low } = useLowDataMode();
  React.useEffect(() => {
    if (error) {
      try { Analytics.track('map.load.failed' as any, { metadata: { reason: String(error?.message ?? error) } }); } catch {}
    }
  }, [error]);
  useImperativeHandle(ref, () => ({
    getMap: () => mapRef.current,
    flyTo: (lng, lat, zoom = 14) => mapRef.current?.flyTo({ center: [lng, lat], zoom, essential: true }),
    fitBounds: (b, padding = 60) => mapRef.current?.fitBounds([[b[0], b[1]], [b[2], b[3]]], { padding, duration: 600 }),
  }));
  if (error) return <div className={`flex items-center justify-center bg-muted text-muted-foreground text-sm rounded-2xl ${className ?? ''}`}>Carte indisponible</div>;
  if (!config) return <Skeleton className={`rounded-2xl ${className ?? ''}`} />;
  return (
    <div className={className}>
      <Map ref={mapRef} mapboxAccessToken={config.mapboxToken} mapStyle={config.styleUrl}
        initialViewState={{
          longitude: initialView?.longitude ?? config.defaultCenter.lng,
          latitude: initialView?.latitude ?? config.defaultCenter.lat,
          zoom: initialView?.zoom ?? config.defaultZoom,
          bearing: initialView?.bearing ?? 0, pitch: initialView?.pitch ?? 0,
          padding: { top: 0, bottom: 0, left: 0, right: 0 },
        }}
        style={{ width: '100%', height: '100%' }}
        attributionControl={false} interactive={interactive}
        maxPitch={low ? 0 : 60}
        fadeDuration={low ? 0 : 300}
        onLoad={(e) => {
          if (!loadedRef.current) {
            loadedRef.current = true;
            try { Analytics.track('map.loaded' as any, { metadata: { provider: config.provider, style: config.styleUrl } }); } catch {}
          }
          onLoad?.();
        }}
        onError={(e) => {
          try { Analytics.track('map.load.failed' as any, { metadata: { reason: String((e as any)?.error?.message ?? 'unknown') } }); } catch {}
        }}
        reuseMaps>
        {interactive && <NavigationControl position="top-right" showCompass={false} />}
        {children}
      </Map>
    </div>
  );
});
