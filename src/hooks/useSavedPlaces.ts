import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export type SavedPlaceKind = "home" | "work" | "favorite";

export interface SavedPlace {
  id: string;
  user_id: string;
  kind: SavedPlaceKind;
  label: string;
  lat: number;
  lng: number;
  landmark_note: string | null;
  created_at: string;
  updated_at: string;
}

/**
 * Lightweight CRUD hook for the user's saved places (Maison / Travail / Favoris).
 */
export function useSavedPlaces() {
  const [places, setPlaces] = useState<SavedPlace[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("saved_places")
      .select("*")
      .order("kind", { ascending: true })
      .order("updated_at", { ascending: false });
    if (error) setError(error.message);
    else setPlaces((data ?? []) as SavedPlace[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    let alive = true;
    refetch().catch(() => {
      if (!alive) return;
      setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, [refetch]);

  const save = useCallback(
    async (input: {
      kind: SavedPlaceKind;
      label: string;
      lat: number;
      lng: number;
      landmark_note?: string | null;
    }) => {
      const { data: u } = await supabase.auth.getUser();
      const uid = u.user?.id;
      if (!uid) throw new Error("Non connecté");
      // For home/work, replace existing one
      if (input.kind === "home" || input.kind === "work") {
        await supabase
          .from("saved_places")
          .delete()
          .eq("user_id", uid)
          .eq("kind", input.kind);
      }
      const { data, error } = await supabase
        .from("saved_places")
        .insert({
          user_id: uid,
          kind: input.kind,
          label: input.label,
          lat: input.lat,
          lng: input.lng,
          landmark_note: input.landmark_note ?? null,
        })
        .select()
        .single();
      if (error) throw error;
      try {
        Analytics.track("saved_place.created" as any, {
          metadata: { kind: input.kind },
        });
      } catch {}
      await refetch();
      return data as SavedPlace;
    },
    [refetch],
  );

  const remove = useCallback(
    async (id: string) => {
      const { error } = await supabase.from("saved_places").delete().eq("id", id);
      if (error) throw error;
      try {
        Analytics.track("saved_place.deleted" as any, { metadata: { id } });
      } catch {}
      await refetch();
    },
    [refetch],
  );

  const markUsed = useCallback((p: SavedPlace) => {
    try {
      Analytics.track("saved_place.used" as any, {
        metadata: { kind: p.kind, id: p.id },
      });
    } catch {}
  }, []);

  return { places, loading, error, save, remove, markUsed, refetch };
}