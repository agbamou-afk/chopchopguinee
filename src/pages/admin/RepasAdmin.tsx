import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, FilterChip, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { UtensilsCrossed, Store, CheckCircle2, ClipboardList } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";
import {
  listAdminRestaurantOverview,
  repasBlockedLabel,
  setRestaurantPublication,
  type RepasAdminRestaurantRow,
  type RepasPublicationAction,
} from "@/lib/repas/discovery";
import { toast } from "sonner";

type Order = {
  id: string;
  restaurant_id: string;
  subtotal_gnf: number;
  state: string;
  fulfillment: string;
  created_at: string;
};

type AdminRestaurant = RepasAdminRestaurantRow;

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
    const [o, overview] = await Promise.all([
      supabase
        .from("food_orders")
        .select("id,restaurant_id,subtotal_gnf,state,fulfillment,created_at")
        .order("created_at", { ascending: false })
        .limit(200),
      listAdminRestaurantOverview().catch(() => [] as AdminRestaurant[]),
    ]);
    setOrders((o.data ?? []) as Order[]);
    setRestaurants(overview);
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
    published: restaurants.filter((r) => r.discoverable).length,
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
        { label: "Visibles clients", value: loading ? "…" : String(stats.published), icon: CheckCircle2 },
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
          columns={[
            "Restaurant",
            "Propriétaire",
            "Boutique liée",
            "Publication",
            "Ouvert",
            "Menu (dispo/total)",
            "Capacités",
            "GPS",
            "Visible / Commandable",
            "Actions",
          ]}
          rows={loading ? [] : restaurants.map((r) => [
            <span className="font-medium">
              {r.name}
              {r.district ? <span className="block text-[11px] text-muted-foreground">{r.district}</span> : null}
            </span>,
            <span className="font-mono text-[11px]">{r.owner_label ?? "—"}</span>,
            r.merchant_store_id ? (
              <span className="text-[11px]">
                {r.merchant_store_name ?? r.merchant_store_id.slice(0, 8)}
                <span className="block text-muted-foreground">{r.merchant_store_status ?? "—"}</span>
              </span>
            ) : (
              <span className="text-[11px] text-muted-foreground">Non liée</span>
            ),
            <span className="flex flex-col gap-1">
              <StatusBadge status={PUBLICATION_LABEL[r.verification_state] ?? r.verification_state} />
              <span className="text-[11px] text-muted-foreground">{r.status}</span>
            </span>,
            r.is_open ? "Oui" : "Non",
            `${r.menu_items_available}/${r.menu_items_total}`,
            <span className="text-[11px] text-muted-foreground">
              {[
                r.delivery_available ? (r.delivery_ready ? "Livraison" : "Livraison (sans GPS)") : null,
                r.pickup_available ? "Retrait" : null,
                r.choppay_enabled ? "Chop Pay" : null,
              ].filter(Boolean).join(" · ") || "Aucune"}
            </span>,
            r.has_coordinates ? "Oui" : "Non",
            <span className="text-[11px]">
              {r.discoverable ? "Visible" : "Non visible"} ·{" "}
              {r.orderable_now ? "Commandable" : "Non commandable"}
              {r.blocked_reason ? (
                <span className="block text-muted-foreground">{repasBlockedLabel(r.blocked_reason)}</span>
              ) : null}
            </span>,
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
                    disabled={busyId === r.id || r.menu_items_total === 0}
                    title={r.menu_items_total === 0 ? "Aucun plat au menu" : undefined}
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
