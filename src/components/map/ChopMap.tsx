import React, { forwardRef, useImperativeHandle, useRef, useState } from 'react';
import Map, { type MapRef, type ViewState } from 'react-map-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import { useMapConfig } from '@/lib/maps';
import { Skeleton } from '@/components/ui/skeleton';
import { Analytics } from '@/lib/analytics/AnalyticsService';
import { useLowDataMode } from '@/hooks/useLowDataMode';
import { MapFallbackCard } from './MapFallbackCard';
import { reportTileStatus } from '@/lib/maps/connectivity';
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
  onClick?: (lngLat: { lng: number; lat: number }) => void;
}
export const ChopMap = forwardRef<ChopMapHandle, Props>(function ChopMap(
  { initialView, className, children, interactive = true, onLoad, onClick }, ref,
) {
  const { config, error } = useMapConfig();
  const mapRef = useRef<MapRef>(null);
  const loadedRef = useRef(false);
  const [runtimeError, setRuntimeError] = useState<string | null>(null);
  const { low } = useLowDataMode();
  React.useEffect(() => {
    if (error) {
      try { Analytics.track('map.load.failed' as any, { metadata: { reason: String(error?.message ?? error) } }); } catch {}
      reportTileStatus('failed');
    }
  }, [error]);
  React.useEffect(() => {
    if (low) reportTileStatus('degraded');
  }, [low]);
  useImperativeHandle(ref, () => ({
    getMap: () => mapRef.current,
    flyTo: (lng, lat, zoom = 14) => mapRef.current?.flyTo({ center: [lng, lat], zoom, essential: true }),
    fitBounds: (b, padding = 60) => mapRef.current?.fitBounds([[b[0], b[1]], [b[2], b[3]]], { padding, duration: 600 }),
  }));
  if (error || runtimeError) {
    return (
      <MapFallbackCard
        className={className}
        message={runtimeError ?? "Mode hors-ligne — vérifiez votre connexion."}
        onRetry={() => { try { window.location.reload(); } catch {} }}
      />
    );
  }
  if (!config) return <Skeleton className={`rounded-2xl ${className ?? ''}`} />;
  if (low) {
    return (
      <div className={`relative chop-map-fallback rounded-2xl ${className ?? ''}`}>
        <div className="pointer-events-none absolute inset-x-6 top-0 h-px bg-gradient-to-r from-transparent via-secondary to-transparent" />
        <div className="absolute inset-0 flex flex-col items-center justify-center text-center px-4">
          <span className="text-[10px] font-bold uppercase tracking-[0.22em] text-muted-foreground">
            Données réduites · carte simplifiée
          </span>
        </div>
        {/* Children (markers) still render so positions can be communicated symbolically */}
      </div>
    );
  }
  return (
    <div className={`relative chop-map-skin ${className ?? ''}`}>
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
        dragPan={interactive}
        scrollZoom={interactive}
        touchZoomRotate={interactive}
        doubleClickZoom={interactive}
        boxZoom={interactive}
        keyboard={interactive}
        maxPitch={low ? 0 : 60}
        fadeDuration={low ? 0 : 300}
        onClick={onClick ? (e: any) => {
          const ll = e?.lngLat;
          if (ll) onClick({ lng: ll.lng, lat: ll.lat });
        } : undefined}
        onLoad={(e) => {
          if (!loadedRef.current) {
            loadedRef.current = true;
            try { Analytics.track('map.loaded' as any, { metadata: { provider: config.provider, style: config.styleUrl } }); } catch {}
          }
          reportTileStatus('ready');
          onLoad?.();
        }}
        onError={(e) => {
          const reason = String((e as any)?.error?.message ?? 'unknown');
          setRuntimeError('Carte indisponible — nous affichons le suivi dès que les tuiles répondent.');
          try { Analytics.track('map.load.failed' as any, { metadata: { reason } }); } catch {}
          reportTileStatus('failed');
        }}
        reuseMaps>
        {children}
      </Map>
      {/* Warm wash overlay — renders above tiles, below markers/UI from parents */}
      <div className="chop-map-wash" aria-hidden />
    </div>
  );
});
