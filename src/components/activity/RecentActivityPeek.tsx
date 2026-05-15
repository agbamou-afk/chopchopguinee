import { useEffect } from "react";
import { useActivityFeed } from "@/lib/activity/useActivityFeed";
import { ActivityRow } from "./ActivityRow";
import { ChevronRight } from "lucide-react";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface RecentActivityPeekProps {
  onSeeAll?: () => void;
}

/**
 * Lightweight ecosystem-continuity card on Home: shows the single most-recent
 * operational event (ride, payment, recharge). Intentionally NOT a feed.
 */
export function RecentActivityPeek({ onSeeAll }: RecentActivityPeekProps) {
  const { items, loading, isAuthenticated } = useActivityFeed("client");
  const last = items[0];

  useEffect(() => {
    if (last) {
      Analytics.track("ecosystem.return_visit", {
        metadata: { last_kind: last.kind, last_status: last.status },
      });
    }
  }, [last?.id]);

  if (!isAuthenticated || loading || !last) return null;

  return (
    <section aria-label="Dernière activité">
      <div className="flex items-end justify-between mb-2">
        <div>
          <h2 className="text-base font-bold text-foreground leading-tight">Dernière activité</h2>
          <p className="text-[11px] text-muted-foreground">Votre fil CHOP CHOP en continu</p>
        </div>
        <button
          type="button"
          onClick={() => {
            Analytics.track("recent_activity_interaction", { metadata: { action: "see_all" } });
            onSeeAll?.();
          }}
          className="inline-flex items-center gap-0.5 text-xs font-semibold text-primary"
        >
          Tout voir <ChevronRight className="w-3 h-3" />
        </button>
      </div>
      <div className="rounded-3xl bg-card shadow-card border border-border/60 p-1">
        <ActivityRow
          item={last}
          compact
          onOpen={() => {
            Analytics.track("recent_activity_interaction", { metadata: { action: "open_item", kind: last.kind } });
            onSeeAll?.();
          }}
        />
      </div>
    </section>
  );
}