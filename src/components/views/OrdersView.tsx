import { useState } from "react";
import { Timer, ShieldCheck } from "lucide-react";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { ActivityTimeline } from "@/components/activity/ActivityTimeline";
import { useActivityFeed } from "@/lib/activity/useActivityFeed";
import { cn } from "@/lib/utils";

type Filter = "all" | "in_progress" | "completed";

const TABS: { key: Filter; label: string }[] = [
  { key: "all", label: "Tout" },
  { key: "in_progress", label: "En cours" },
  { key: "completed", label: "Historique" },
];

export function OrdersView() {
  const [filter, setFilter] = useState<Filter>("all");
  const { items, loading } = useActivityFeed("client");

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader
        title="Activité"
        subtitle="Courses, paiements, recharges — votre fil CHOP CHOP"
      />

      <div className="mt-4">
        <LiveStrip
          stats={[
            { icon: Timer, label: "Mises à jour en direct", bg: "bg-primary/10", tone: "text-primary" },
            { icon: ShieldCheck, label: "Reçus traçables", bg: "bg-success/10", tone: "text-success" },
          ]}
        />
      </div>

      {/* Filter tabs */}
      <div className="px-4 mt-4 mb-4">
        <div className="flex gap-2 bg-muted rounded-2xl p-1">
          {TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setFilter(t.key)}
              className={cn(
                "flex-1 py-2 rounded-xl text-sm font-semibold transition-colors",
                filter === t.key
                  ? "gradient-wallet text-primary-foreground shadow-card"
                  : "text-muted-foreground hover:text-foreground",
              )}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <div className="px-3 pb-28">
        <ActivityTimeline items={items} loading={loading} filter={filter} />
      </div>
    </div>
  );
}
