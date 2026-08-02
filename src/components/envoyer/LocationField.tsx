import { useEffect, useRef, useState } from "react";
import { Loader2, MapPin, Crosshair, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { searchPlaces, reverseGeocode, type PlaceSearchResult } from "@/lib/maps/placeSearch";
import { useGeolocation } from "@/hooks/useGeolocation";

export interface PickedLocation {
  lat: number;
  lng: number;
  label: string;
}

interface LocationFieldProps {
  id: string;
  title: string;
  placeholder: string;
  value: PickedLocation | null;
  onChange: (loc: PickedLocation | null) => void;
  /** Offer a "use my position" shortcut (pickup only). */
  allowCurrentPosition?: boolean;
}

/**
 * Reuses the existing maps-search edge function for place lookup — no new
 * geocoding pipeline. Never fabricates coordinates: if search fails, the
 * field stays empty and says so.
 */
export function LocationField({
  id,
  title,
  placeholder,
  value,
  onChange,
  allowCurrentPosition,
}: LocationFieldProps) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<PlaceSearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [failed, setFailed] = useState(false);
  const [locating, setLocating] = useState(false);
  const timer = useRef<number | null>(null);
  const geo = useGeolocation({ manualOnly: true });

  useEffect(() => {
    if (timer.current) window.clearTimeout(timer.current);
    const q = query.trim();
    if (q.length < 2) {
      setResults([]);
      setFailed(false);
      return;
    }
    timer.current = window.setTimeout(async () => {
      setSearching(true);
      const { results: r, provider } = await searchPlaces(q, { limit: 6 });
      setResults(r);
      setFailed(provider === "error" || (provider !== "none" && r.length === 0));
      setSearching(false);
    }, 300);
    return () => {
      if (timer.current) window.clearTimeout(timer.current);
    };
  }, [query]);

  const useMyPosition = async () => {
    setLocating(true);
    setQuery("");
    setResults([]);
    geo.request();
  };

  // Stop the spinner honestly when the browser refuses the permission.
  useEffect(() => {
    if (locating && (geo.status === "denied" || geo.status === "blocked" || geo.status === "unavailable")) {
      setLocating(false);
    }
  }, [geo.status, locating]);

  // The geolocation hook resolves asynchronously; adopt the position as soon
  // as it lands so "Ma position" never shows a stale/empty state.
  useEffect(() => {
    if (!locating || !geo.position) return;
    const p = geo.position;
    let alive = true;
    (async () => {
      const rev = await reverseGeocode(p.lat, p.lng);
      if (!alive) return;
      onChange({ lat: p.lat, lng: p.lng, label: rev?.label ?? "Ma position actuelle" });
      setLocating(false);
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [geo.position, locating]);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <label htmlFor={id} className="text-[13px] font-semibold text-foreground">
          {title}
        </label>
        {allowCurrentPosition && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-9 px-2 text-[12px]"
            onClick={useMyPosition}
            disabled={locating}
          >
            {locating ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <Crosshair className="w-3.5 h-3.5" />
            )}
            Ma position
          </Button>
        )}
      </div>

      {value ? (
        <button
          type="button"
          onClick={() => onChange(null)}
          className="w-full flex items-start gap-2 rounded-xl border border-primary/25 bg-primary/5 p-3 text-left min-h-[48px]"
          aria-label={`${title} : ${value.label}. Appuyez pour modifier.`}
        >
          <MapPin className="w-4 h-4 text-primary mt-0.5 shrink-0" />
          <span className="text-[13px] text-foreground leading-snug break-words">{value.label}</span>
        </button>
      ) : (
        <>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              id={id}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={placeholder}
              className="pl-9 h-12"
              autoComplete="off"
              inputMode="search"
            />
            {searching && (
              <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-muted-foreground" />
            )}
          </div>
          {results.length > 0 && (
            <ul className="rounded-xl border border-border divide-y divide-border overflow-hidden">
              {results.map((r) => (
                <li key={r.id}>
                  <button
                    type="button"
                    className="w-full text-left px-3 py-3 min-h-[48px] active:bg-muted"
                    onClick={() => {
                      onChange({ lat: r.lat, lng: r.lng, label: r.label });
                      setResults([]);
                      setQuery("");
                    }}
                  >
                    <p className="text-[13px] font-medium text-foreground">{r.label}</p>
                    {r.secondary_label && (
                      <p className="text-[11px] text-muted-foreground">{r.secondary_label}</p>
                    )}
                  </button>
                </li>
              ))}
            </ul>
          )}
          {failed && (
            <p className="text-[12px] text-muted-foreground">
              Aucun résultat. Vérifiez votre connexion ou précisez un repère connu.
            </p>
          )}
        </>
      )}
    </div>
  );
}