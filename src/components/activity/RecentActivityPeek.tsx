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
      <div className="flex items-center justify-between mb-2 px-0.5">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
          Dernière activité
        </h2>
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
      <div className="rounded-3xl card-warm p-1 relative overflow-hidden">
        <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam opacity-70" aria-hidden />
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