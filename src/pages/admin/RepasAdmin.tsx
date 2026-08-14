import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { UtensilsCrossed, Store, CheckCircle2, ClipboardList } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";
import { setRestaurantPublication, type RepasPublicationAction } from "@/lib/repas/discovery";
import { toast } from "sonner";

type Order = {
  id: string;
  restaurant_id: string;
  subtotal_gnf: number;
  state: string;
  fulfillment: string;
  created_at: string;
};

type AdminRestaurant = {
  id: string;
  name: string;
  district: string | null;
  cuisine: string | null;
  status: string;
  verification_state: string;
  is_open: boolean;
  choppay_enabled: boolean;
  menu_count: number;
};

const PUBLICATION_LABEL: Record<string, string> = {
  verified: "Publié",
  none: "Brouillon",
  suspended: "Suspendu",
  rejected: "Refusé",
};

export default function RepasAdmin() {
  const [f, setF] = useState<"Tous" | "En cours" | "Livrées">("Tous");
  const [orders, setOrders] = useState<Order[]>([]);
  const [restaurants, setRestaurants] = useState<AdminRestaurant[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    const [o, r, m] = await Promise.all([
      supabase
        .from("food_orders")
        .select("id,restaurant_id,subtotal_gnf,state,fulfillment,created_at")
        .order("created_at", { ascending: false })
        .limit(200),
      supabase
        .from("food_restaurants")
        .select("id,name,district,cuisine,status,verification_state,is_open,choppay_enabled")
        .order("created_at", { ascending: false })
        .limit(500),
      supabase.from("food_menu_items").select("restaurant_id").limit(5000),
    ]);
    setOrders((o.data ?? []) as Order[]);
    const counts: Record<string, number> = {};
    ((m.data ?? []) as Array<{ restaurant_id: string }>).forEach((x) => {
      counts[x.restaurant_id] = (counts[x.restaurant_id] ?? 0) + 1;
    });
    setRestaurants(
      ((r.data ?? []) as Array<Record<string, unknown>>).map((x) => ({
        id: x.id as string,
        name: x.name as string,
        district: (x.district ?? null) as string | null,
        cuisine: (x.cuisine ?? null) as string | null,
        status: x.status as string,
        verification_state: x.verification_state as string,
        is_open: !!x.is_open,
        choppay_enabled: !!x.choppay_enabled,
        menu_count: counts[x.id as string] ?? 0,
      })),
    );
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, []);

  const restoNames = useMemo(
    () => Object.fromEntries(restaurants.map((r) => [r.id, r.name])),
    [restaurants],
  );

  const act = async (id: string, action: RepasPublicationAction) => {
    setBusyId(id);
    try {
      await setRestaurantPublication(id, action);
      toast.success(
        action === "publish"
          ? "Restaurant publié"
          : action === "suspend"
            ? "Restaurant suspendu"
            : action === "reject"
              ? "Restaurant refusé"
              : "Publication retirée",
      );
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusyId(null);
    }
  };

  const stats = useMemo(() => ({
    restos: restaurants.length,
    published: restaurants.filter((r) => r.verification_state === "verified" && r.status === "active").length,
    orders: orders.length,
    inflight: orders.filter((o) => ["placed", "confirmed", "preparing", "ready"].includes(o.state)).length,
  }), [orders, restaurants]);

  const filtered = useMemo(() => {
    if (f === "En cours") return orders.filter((o) => ["placed", "confirmed", "preparing", "ready"].includes(o.state));
    if (f === "Livrées") return orders.filter((o) => ["delivered", "picked_up"].includes(o.state));
    return orders;
  }, [orders, f]);

  return (
    <ModulePage module="repas" title="Repas" subtitle="Restaurants et commandes réelles">
      <StatGrid items={[
        { label: "Restaurants", value: loading ? "…" : String(stats.restos), icon: Store },
        { label: "Publiés", value: loading ? "…" : String(stats.published), icon: CheckCircle2 },
        { label: "Commandes", value: loading ? "…" : String(stats.orders), icon: ClipboardList },
        { label: "En cours", value: loading ? "…" : String(stats.inflight), icon: UtensilsCrossed },
      ]} />

      <div className="space-y-2">
        <h2 className="text-sm font-semibold text-foreground">Publication des restaurants</h2>
        <p className="text-xs text-muted-foreground">
          Un restaurant n’est visible par les clients qu’une fois publié ici. Publier exige un
          menu réel.
        </p>
        <DataTable
          columns={["Restaurant", "Quartier", "Menu", "État", "Ouvert", "Actions"]}
          rows={loading ? [] : restaurants.map((r) => [
            <span className="font-medium">{r.name}</span>,
            r.district ?? "—",
            `${r.menu_count} plat${r.menu_count > 1 ? "s" : ""}`,
            <StatusBadge status={PUBLICATION_LABEL[r.verification_state] ?? r.verification_state} />,
            r.is_open ? "Oui" : "Non",
            <div className="flex gap-1.5">
              {r.verification_state === "verified" && r.status === "active" ? (
                <>
                  <button
                    disabled={busyId === r.id}
                    onClick={() => act(r.id, "unpublish")}
                    className="px-2 py-1 rounded-lg border border-border text-[11px] disabled:opacity-50"
                  >
                    Retirer
                  </button>
                  <button
                    disabled={busyId === r.id}
                    onClick={() => act(r.id, "suspend")}
                    className="px-2 py-1 rounded-lg border border-destructive/40 text-destructive text-[11px] disabled:opacity-50"
                  >
                    Suspendre
                  </button>
                </>
              ) : (
                <>
                  <button
                    disabled={busyId === r.id || r.menu_count === 0}
                    title={r.menu_count === 0 ? "Aucun plat au menu" : undefined}
                    className="px-2 py-1 rounded-lg gradient-primary text-primary-foreground text-[11px] disabled:opacity-40"
                    onClick={() => act(r.id, "publish")}
                  >
                    Publier
                  </button>
                  <button
                    disabled={busyId === r.id}
                    onClick={() => act(r.id, "reject")}
                    className="px-2 py-1 rounded-lg border border-border text-[11px] disabled:opacity-50"
                  >
                    Refuser
                  </button>
                </>
              )}
            </div>,
          ])}
        />
      </div>

      <AdminToolbar placeholder="Recherche à connecter..." />
      <div className="flex gap-2 flex-wrap">
        {(["Tous", "En cours", "Livrées"] as const).map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <DataTable
        columns={["ID", "Restaurant", "Total", "Fulfillment", "Statut", "Créée"]}
        rows={loading ? [] : filtered.map((o) => [
          <span className="font-mono text-xs">{o.id.slice(0, 8)}…</span>,
          restoNames[o.restaurant_id] ?? "—",
          formatGNF(Number(o.subtotal_gnf || 0)),
          o.fulfillment,
          <StatusBadge status={o.state} />,
          new Date(o.created_at).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" }),
        ])}
      />
    </ModulePage>
  );
}
