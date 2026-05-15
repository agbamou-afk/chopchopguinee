import { useEffect, useMemo, useState } from "react";
import { ActivityRow } from "./ActivityRow";
import { ActivityDetailSheet } from "./ActivityDetailSheet";
import { groupActivities, type ActivityItem } from "@/lib/activity/types";
import { Skeleton } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/EmptyState";
import { History } from "lucide-react";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface ActivityTimelineProps {
  items: ActivityItem[];
  loading?: boolean;
  /** Optional filter: "all" | "in_progress" | "completed". */
  filter?: "all" | "in_progress" | "completed";
}

export function ActivityTimeline({ items, loading, filter = "all" }: ActivityTimelineProps) {
  const [opened, setOpened] = useState<ActivityItem | null>(null);

  const visible = useMemo(() => {
    if (filter === "in_progress") return items.filter((i) => i.status === "in_progress" || i.status === "pending");
    if (filter === "completed") return items.filter((i) => i.status === "completed" || i.status === "cancelled" || i.status === "failed");
    return items;
  }, [items, filter]);

  const groups = useMemo(() => groupActivities(visible), [visible]);

  useEffect(() => {
    let timer: number | undefined;
    const onScroll = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        Analytics.track("activity.timeline_scrolled", {
          metadata: { count: visible.length, filter },
        });
      }, 600);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.clearTimeout(timer);
    };
  }, [visible.length, filter]);

  if (loading) {
    return (
      <div className="space-y-2 px-1">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-16 w-full rounded-2xl" />
        ))}
      </div>
    );
  }

  if (groups.length === 0) {
    return (
      <EmptyState
        icon={History}
        title="Aucune activité"
        description="Vos courses, paiements et recharges apparaîtront ici dès qu'ils auront lieu."
      />
    );
  }

  return (
    <div className="space-y-6">
      {groups.map((g) => (
        <section key={g.key} aria-label={g.label}>
          <div className="px-3 mb-2 flex items-center gap-2">
            <h3 className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
              {g.label}
            </h3>
            <span className="h-px flex-1 bg-border/60" />
          </div>
          <div className="space-y-1">
            {g.items.map((it) => (
              <ActivityRow
                key={it.id}
                item={it}
                onOpen={(x) => {
                  setOpened(x);
                  Analytics.track("activity.item_opened", {
                    metadata: { kind: x.kind, status: x.status },
                  });
                }}
              />
            ))}
          </div>
        </section>
      ))}
      <ActivityDetailSheet item={opened} onClose={() => setOpened(null)} />
    </div>
  );
}