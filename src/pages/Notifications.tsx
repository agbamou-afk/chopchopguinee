import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Bell, Check, Trash2, Wallet, Car, Package, ShoppingBag, Info,
  LifeBuoy, Inbox,
} from "lucide-react";
import { AppShell } from "@/components/ui/AppShell";
import { PageHeader } from "@/components/ui/PageHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import {
  notifications,
  groupOfKind,
  type AppNotification,
  type NotificationKind,
  type NotificationGroup,
} from "@/lib/notifications";
import { Seo } from "@/components/Seo";
import { Analytics } from "@/lib/analytics/AnalyticsService";

const KIND_ICON: Record<NotificationKind, typeof Bell> = {
  wallet: Wallet,
  ride: Car,
  delivery: Package,
  order: Package,
  marche: ShoppingBag,
  support: LifeBuoy,
  system: Info,
};

const KIND_TINT: Record<NotificationKind, string> = {
  wallet: "bg-brand-green-muted text-primary",
  ride: "bg-brand-yellow-muted text-secondary-foreground",
  delivery: "bg-brand-yellow-muted text-secondary-foreground",
  order: "bg-brand-yellow-muted text-secondary-foreground",
  marche: "bg-brand-red-muted text-destructive",
  support: "bg-muted text-foreground",
  system: "bg-muted text-foreground",
};

const GROUP_META: Record<
  NotificationGroup,
  { label: string; icon: typeof Bell }
> = {
  wallet: { label: "CHOPWallet", icon: Wallet },
  rides: { label: "Courses", icon: Car },
  orders: { label: "Commandes", icon: Package },
  support: { label: "Support", icon: LifeBuoy },
  marketplace: { label: "Marché", icon: ShoppingBag },
  other: { label: "Autres", icon: Info },
};

const GROUP_ORDER: NotificationGroup[] = [
  "wallet", "rides", "orders", "support", "marketplace", "other",
];

function formatTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.round(diff / 60000);
  if (m < 1) return "À l'instant";
  if (m < 60) return `Il y a ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `Il y a ${h} h`;
  return new Date(iso).toLocaleDateString("fr-FR", { day: "2-digit", month: "short" });
}

type Filter = "all" | NotificationGroup;

const NotificationsPage = () => {
  const navigate = useNavigate();
  const [items, setItems] = useState<AppNotification[]>([]);
  const [filter, setFilter] = useState<Filter>("all");

  useEffect(() => {
    const refresh = () => setItems(notifications.list());
    refresh();
    window.addEventListener("chopchop:notifications:update", refresh);
    return () => window.removeEventListener("chopchop:notifications:update", refresh);
  }, []);

  // Group + counts
  const grouped = useMemo(() => {
    const map = new Map<NotificationGroup, AppNotification[]>();
    for (const g of GROUP_ORDER) map.set(g, []);
    for (const n of items) map.get(groupOfKind(n.kind))!.push(n);
    return map;
  }, [items]);

  const totalUnread = items.filter((n) => !n.read).length;

  const visibleGroups = GROUP_ORDER.filter((g) => {
    const list = grouped.get(g) ?? [];
    if (list.length === 0) return false;
    return filter === "all" || filter === g;
  });

  const clearGroup = (g: NotificationGroup) => {
    const ids = (grouped.get(g) ?? []).map((n) => n.id);
    notifications.removeMany(ids);
  };
  const markGroupRead = (g: NotificationGroup) => {
    const ids = (grouped.get(g) ?? []).filter((n) => !n.read).map((n) => n.id);
    notifications.markManyRead(ids);
  };

  return (
    <AppShell withBottomNav={false}>
      <Seo title="Notifications — CHOP CHOP" description="Vos alertes courses, livraisons, paiements et marché." canonical="/notifications" />
      <PageHeader
        title="Notifications"
        onBack={() => navigate(-1)}
        right={
          items.length > 0 ? (
            <div className="flex items-center gap-1">
              <button
                onClick={() => notifications.markAllRead()}
                className="p-2 rounded-full hover:bg-muted disabled:opacity-40"
                disabled={totalUnread === 0}
                aria-label="Tout marquer lu"
              >
                <Check className="w-5 h-5" />
              </button>
              <button
                onClick={() => {
                  if (confirm("Tout effacer ?")) notifications.clear();
                }}
                className="p-2 rounded-full hover:bg-muted"
                aria-label="Tout supprimer"
              >
                <Trash2 className="w-5 h-5 text-destructive" />
              </button>
            </div>
          ) : null
        }
      />

      {/* Group filter chips */}
      {items.length > 0 && (
        <div className="px-4 pt-2 pb-1 flex gap-2 overflow-x-auto no-scrollbar">
          <FilterChip
            label="Tout"
            count={totalUnread}
            active={filter === "all"}
            onClick={() => setFilter("all")}
          />
          {GROUP_ORDER.map((g) => {
            const list = grouped.get(g) ?? [];
            if (list.length === 0) return null;
            const unread = list.filter((n) => !n.read).length;
            return (
              <FilterChip
                key={g}
                label={GROUP_META[g].label}
                count={unread}
                active={filter === g}
                onClick={() => setFilter(g)}
              />
            );
          })}
        </div>
      )}

      <div className="px-4 pt-3 pb-6 space-y-5">
        {items.length === 0 ? (
          <EmptyState
            icon={Bell}
            title="Aucune notification"
            description="Vos alertes courses, livraisons, paiements et marché s'afficheront ici."
          />
        ) : visibleGroups.length === 0 ? (
          <EmptyState
            icon={Inbox}
            title="Rien dans cette catégorie"
            description="Sélectionnez « Tout » pour voir l'ensemble de vos notifications."
          />
        ) : (
          visibleGroups.map((g) => {
            const list = grouped.get(g)!;
            const unread = list.filter((n) => !n.read).length;
            const meta = GROUP_META[g];
            const GIcon = meta.icon;
            return (
              <section key={g} aria-label={meta.label}>
                <header className="flex items-center justify-between mb-2 px-1">
                  <div className="flex items-center gap-2">
                    <GIcon className="w-4 h-4 text-muted-foreground" />
                    <h2 className="text-sm font-semibold text-foreground">
                      {meta.label}
                    </h2>
                    {unread > 0 && (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-primary text-primary-foreground">
                        {unread}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-1">
                    {unread > 0 && (
                      <button
                        onClick={() => markGroupRead(g)}
                        className="text-xs text-muted-foreground hover:text-foreground px-2 py-1 rounded-md"
                      >
                        Tout lu
                      </button>
                    )}
                    <button
                      onClick={() => clearGroup(g)}
                      className="text-xs text-destructive/80 hover:text-destructive px-2 py-1 rounded-md"
                      aria-label={`Effacer ${meta.label}`}
                    >
                      Effacer
                    </button>
                  </div>
                </header>
                <ul className="space-y-2">
                  {list.map((n) => {
                    const Icon = KIND_ICON[n.kind] ?? Bell;
                    return (
                      <li
                        key={n.id}
                        onClick={() => {
                          notifications.markRead(n.id);
                          if (n.link) {
                            Analytics.track("notification.deep_link.followed", {
                              metadata: { kind: n.kind, link: n.link },
                            });
                            navigate(n.link);
                          }
                        }}
                        className={`flex gap-3 p-3 rounded-2xl cursor-pointer transition ${
                          n.read
                            ? "bg-card"
                            : "bg-card shadow-card border border-primary/30"
                        }`}
                      >
                        <span className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${KIND_TINT[n.kind] ?? "bg-muted text-foreground"}`}>
                          <Icon className="w-5 h-5" />
                        </span>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between gap-2">
                            <p className={`text-sm truncate ${n.read ? "font-medium text-foreground/80" : "font-semibold text-foreground"}`}>
                              {n.title}
                            </p>
                            {!n.read && (
                              <span className="w-2 h-2 rounded-full bg-primary shrink-0" aria-label="Non lu" />
                            )}
                          </div>
                          <p className="text-xs text-muted-foreground line-clamp-2">{n.body}</p>
                          <p className="text-[10px] text-muted-foreground mt-1">{formatTime(n.createdAt)}</p>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </section>
            );
          })
        )}
      </div>
    </AppShell>
  );
};

function FilterChip({
  label, count, active, onClick,
}: { label: string; count: number; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`shrink-0 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border transition ${
        active
          ? "bg-primary text-primary-foreground border-primary"
          : "bg-card text-foreground border-border hover:bg-muted"
      }`}
    >
      <span>{label}</span>
      {count > 0 && (
        <span className={`text-[10px] font-bold px-1.5 rounded-full ${
          active ? "bg-primary-foreground/20" : "bg-primary/15 text-primary"
        }`}>
          {count}
        </span>
      )}
    </button>
  );
}

export default NotificationsPage;
