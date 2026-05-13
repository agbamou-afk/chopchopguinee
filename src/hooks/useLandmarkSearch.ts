import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export interface Landmark {
  id: string;
  name: string;
  aliases: string[];
  category: string;
  commune: string | null;
  neighborhood: string | null;
  lat: number;
  lng: number;
  popularity: number;
}

/**
 * Searches the Conakry landmark catalog. Debounced; falls back to
 * the most popular landmarks when query is empty.
 */
export function useLandmarkSearch(query: string, opts: { limit?: number } = {}) {
  const { limit = 8 } = opts;
  const [results, setResults] = useState<Landmark[]>([]);
  const [loading, setLoading] = useState(false);
  const tRef = useRef<number | null>(null);

  useEffect(() => {
    if (tRef.current) window.clearTimeout(tRef.current);
    const q = query.trim();
    tRef.current = window.setTimeout(async () => {
      setLoading(true);
      try {
        let req = supabase
          .from("landmarks")
          .select("id,name,aliases,category,commune,neighborhood,lat,lng,popularity")
          .eq("active", true)
          .order("popularity", { ascending: false })
          .limit(limit);
        if (q.length >= 2) {
          // ilike on name OR alias array contains match
          req = req.or(`name.ilike.%${q}%,aliases.cs.{${q}}`);
        }
        const { data, error } = await req;
        if (!error) setResults((data ?? []) as Landmark[]);
      } finally {
        setLoading(false);
      }
    }, 200);
    return () => {
      if (tRef.current) window.clearTimeout(tRef.current);
    };
  }, [query, limit]);

  return { results, loading };
}