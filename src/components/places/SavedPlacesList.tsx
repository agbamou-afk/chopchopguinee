import { Home, Briefcase, Star, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useSavedPlaces, type SavedPlace } from "@/hooks/useSavedPlaces";

const ICONS = {
  home: Home,
  work: Briefcase,
  favorite: Star,
} as const;

const LABELS = {
  home: "Maison",
  work: "Travail",
  favorite: "Favori",
} as const;

interface Props {
  onSelect: (p: SavedPlace) => void;
  onAddRequest?: (kind: SavedPlace["kind"]) => void;
  showAddCTA?: boolean;
  compact?: boolean;
}

/**
 * Renders the user's saved places. Surfaces empty slots for Maison and
 * Travail (one-tap shortcuts in ride booking).
 */
export function SavedPlacesList({
  onSelect,
  onAddRequest,
  showAddCTA = true,
  compact,
}: Props) {
  const { places, loading, remove, markUsed } = useSavedPlaces();

  const home = places.find((p) => p.kind === "home");
  const work = places.find((p) => p.kind === "work");
  const favorites = places.filter((p) => p.kind === "favorite");

  if (loading) {
    return (
      <div className="text-xs text-muted-foreground px-1">Chargement…</div>
    );
  }

  const renderShortcut = (kind: "home" | "work", place: SavedPlace | undefined) => {
    const Icon = ICONS[kind];
    if (place) {
      return (
        <button
          key={kind}
          type="button"
          onClick={() => {
            markUsed(place);
            onSelect(place);
          }}
          className="flex items-center gap-2 rounded-xl border border-border bg-card px-3 py-2 text-left hover:border-primary transition-colors"
        >
          <Icon className="h-4 w-4 text-primary shrink-0" />
          <div className="min-w-0">
            <p className="text-xs font-medium leading-tight">{LABELS[kind]}</p>
            <p className="text-[10px] text-muted-foreground truncate">{place.label}</p>
          </div>
        </button>
      );
    }
    if (!showAddCTA) return null;
    return (
      <button
        key={kind}
        type="button"
        onClick={() => onAddRequest?.(kind)}
        className="flex items-center gap-2 rounded-xl border border-dashed border-border px-3 py-2 text-left text-muted-foreground hover:border-primary hover:text-foreground transition-colors"
      >
        <Icon className="h-4 w-4 shrink-0" />
        <div className="min-w-0">
          <p className="text-xs font-medium leading-tight">{LABELS[kind]}</p>
          <p className="text-[10px] truncate">Ajouter</p>
        </div>
      </button>
    );
  };

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 gap-2">
        {renderShortcut("home", home)}
        {renderShortcut("work", work)}
      </div>

      {favorites.length > 0 && (
        <div className="space-y-1">
          {favorites.map((p) => (
            <div
              key={p.id}
              className="flex items-center gap-2 rounded-xl border border-border bg-card px-3 py-2"
            >
              <Star className="h-4 w-4 text-amber-500 shrink-0" />
              <button
                type="button"
                onClick={() => {
                  markUsed(p);
                  onSelect(p);
                }}
                className="flex-1 min-w-0 text-left"
              >
                <p className="text-xs font-medium truncate">{p.label}</p>
                {p.landmark_note && (
                  <p className="text-[10px] text-muted-foreground truncate">
                    {p.landmark_note}
                  </p>
                )}
              </button>
              {!compact && (
                <Button
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7 text-muted-foreground hover:text-destructive"
                  onClick={() => remove(p.id).catch(() => {})}
                  aria-label="Supprimer"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              )}
            </div>
          ))}
        </div>
      )}

      {showAddCTA && favorites.length === 0 && (
        <button
          type="button"
          onClick={() => onAddRequest?.("favorite")}
          className="w-full flex items-center justify-center gap-1.5 rounded-xl border border-dashed border-border py-2 text-xs text-muted-foreground hover:text-foreground hover:border-primary transition-colors"
        >
          <Plus className="h-3.5 w-3.5" />
          Ajouter un favori
        </button>
      )}
    </div>
  );
}