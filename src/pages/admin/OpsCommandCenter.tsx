import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  Activity, AlertTriangle, Bike, CheckCircle2, Coins, LifeBuoy, Mail,
  Map as MapIcon, RefreshCw, ShoppingBag, Store, UtensilsCrossed, Wallet,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";

type Status = "ready" | "action" | "degraded" | "unknown";

interface ReadinessItem {
  key: string;
  label: string;
  status: Status;
  detail: string;
  href?: string;
}

interface CountCard {
  key: string;
  label: string;
  value: number | null;
  href?: string;
  hint?: string;
  icon: typeof Activity;
  hidden?: boolean;
}

const STATUS_META: Record<Status, { label: string; cls: string }> = {
  ready:    { label: "Prêt",                cls: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300" },
  action:   { label: "Action requise",      cls: "bg-amber-500/10 text-amber-700 dark:text-amber-300" },
  degraded: { label: "Mode dégradé",        cls: "bg-orange-500/10 text-orange-700 dark:text-orange-300" },
  unknown:  { label: "À vérifier",          cls: "bg-muted text-muted-foreground" },
};

const REFRESH_MS = 60_000;
const DRIVER_TARGET = 10;

function startOfTodayISO() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
}

async function safeCount(
  table: string,
  build?: (q: ReturnType<typeof supabase.from>) => any,
): Promise<number | null> {
  try {
    let q: any = supabase.from(table as any).select("*", { count: "exact", head: true });
    if (build) q = build(q);
    const { count, error } = await q;
    if (error) return null;
    return count ?? 0;
  } catch {
    return null;
  }
}

export default function OpsCommandCenter() {
  const { role } = useAdminAuth();
  const isGod = role === "god_admin";
  const isFinance = role === "finance_admin" || isGod;
  const isOps = role === "operations_admin" || isGod;

  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);

  const [readiness, setReadiness] = useState<ReadinessItem[]>([]);
  const [today, setToday] = useState<CountCard[]>([]);
  const [urgent, setUrgent] = useState<{ support: number | null; pendingDrivers: number | null;
    pendingTopups: number | null; pendingCashouts: number | null; mapDups: number | null;
    storesNoLocation: number | null; restaurantsNoMenu: number | null; }>({
    support: null, pendingDrivers: null, pendingTopups: null, pendingCashouts: null,
    mapDups: null, storesNoLocation: null, restaurantsNoMenu: null,
  });
  const [masterBalance, setMasterBalance] = useState<number | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const since = startOfTodayISO();

    const [
      ridesToday, ridesActive, ridesCompleted, ridesCancelled,
      missionsActive, missionsDelivered,
      repasToday, repasPending,
      marcheInterests, supportOpen,
      driversApproved, driversOnlineRecent,
      pendingTopups, pendingCashouts, supportHigh,
      pendingDrivers, mapDups, storesNoLocation, restaurantsNoMenu,
    ] = await Promise.all([
      safeCount("rides", (q) => q.gte("created_at", since)),
      safeCount("rides", (q) => q.in("status", ["requested", "accepted", "en_route", "in_progress", "arrived"])),
      safeCount("rides", (q) => q.eq("status", "completed").gte("created_at", since)),
      safeCount("rides", (q) => q.eq("status", "cancelled").gte("created_at", since)),
      safeCount("missions", (q) => q.in("status", ["assigned", "in_progress", "picked_up"])),
      safeCount("missions", (q) => q.eq("status", "delivered").gte("created_at", since)),
      safeCount("food_orders", (q) => q.gte("created_at", since)),
      safeCount("food_orders", (q) => q.in("status", ["pending", "accepted", "preparing", "ready"])),
      safeCount("listing_interests", (q) => q.gte("created_at", since)),
      safeCount("support_issues", (q) => q.in("status", ["open", "in_progress", "pending"])),
      safeCount("driver_profiles", (q) => q.eq("status", "approved")),
      safeCount("driver_locations", (q) =>
        q.gte("updated_at", new Date(Date.now() - 30 * 60_000).toISOString())),
      isFinance ? safeCount("topup_requests", (q) => q.eq("status", "pending")) : Promise.resolve(null),
      isFinance ? safeCount("driver_cashout_requests", (q) => q.eq("status", "pending")) : Promise.resolve(null),
      safeCount("support_issues", (q) => q.in("status", ["open", "in_progress"]).eq("severity", "high")),
      safeCount("driver_applications", (q) => q.eq("status", "submitted")),
      safeCount("map_place_duplicate_candidates", (q) => q.eq("status", "open")),
      safeCount("merchant_stores", (q) => q.is("location_lat", null)),
      safeCount("food_restaurants", (q) => q.eq("is_active", true)),
    ]);

    // Master balance: God Admin only
    let master: number | null = null;
    if (isGod) {
      try {
        const { data } = await supabase.rpc("wallet_get_master_balance");
        master = typeof data === "number" ? data : null;
      } catch { master = null; }
    }
    setMasterBalance(master);

    // Readiness strip
    const driversTested = driversOnlineRecent ?? 0;
    const r: ReadinessItem[] = [
      {
        key: "smtp",
        label: "SMTP",
        status: "unknown",
        detail: "Vérifier la configuration production. Voir checklist.",
        href: "/admin/settings",
      },
      {
        key: "drivers",
        label: "Chauffeurs approuvés",
        status: (driversApproved ?? 0) >= DRIVER_TARGET ? "ready" : "action",
        detail: `${driversApproved ?? "?"}/${DRIVER_TARGET} approuvés`,
        href: "/admin/drivers",
      },
      {
        key: "drivers_online",
        label: "Chauffeurs récents",
        status: driversTested >= 5 ? "ready" : "action",
        detail: `${driversTested} actifs <30 min`,
        href: "/admin/map/driver-signals",
      },
      {
        key: "topup",
        label: "Recharge OM",
        status: "action",
        detail: "Vérification opérateur manuelle. Aucun crédit automatique.",
        href: "/admin/wallet/reconciliation",
      },
      {
        key: "maps",
        label: "Cartes",
        status: "ready",
        detail: "Mode dégradé disponible.",
        href: "/admin/map/routing",
      },
      {
        key: "support",
        label: "Support",
        status: (supportOpen ?? 0) > 0 ? "action" : "ready",
        detail: `${supportOpen ?? "?"} tickets ouverts`,
        href: "/admin/support",
      },
    ];
    setReadiness(r);

    setToday([
      { key: "rides_today", label: "Courses créées", value: ridesToday, href: "/admin/orders", icon: Bike },
      { key: "rides_active", label: "Courses actives", value: ridesActive, href: "/admin/live", icon: Activity },
      { key: "rides_done", label: "Courses terminées", value: ridesCompleted, href: "/admin/orders", icon: CheckCircle2 },
      { key: "rides_cxl", label: "Courses annulées", value: ridesCancelled, href: "/admin/orders", icon: AlertTriangle },
      { key: "missions_active", label: "Missions actives", value: missionsActive, href: "/admin/orders", icon: Activity },
      { key: "missions_done", label: "Missions livrées", value: missionsDelivered, href: "/admin/orders", icon: CheckCircle2 },
      { key: "repas_today", label: "Commandes Repas", value: repasToday, href: "/admin/repas", icon: UtensilsCrossed },
      { key: "repas_pending", label: "Repas en cours", value: repasPending, href: "/admin/repas", icon: UtensilsCrossed },
      { key: "marche_interest", label: "Intérêts Marché", value: marcheInterests, href: "/admin/marche", icon: ShoppingBag },
      { key: "support_open", label: "Tickets ouverts", value: supportOpen, href: "/admin/support", icon: LifeBuoy },
      { key: "topup_pending", label: "Top-ups en attente", value: pendingTopups, href: "/admin/wallet/reconciliation",
        icon: Wallet, hidden: !isFinance },
      { key: "cashout_pending", label: "Cashouts en attente", value: pendingCashouts, href: "/admin/wallet/driver-cashouts",
        icon: Coins, hidden: !isFinance },
    ]);

    setUrgent({
      support: supportHigh,
      pendingDrivers,
      pendingTopups: isFinance ? pendingTopups : null,
      pendingCashouts: isFinance ? pendingCashouts : null,
      mapDups,
      storesNoLocation,
      restaurantsNoMenu,
    });

    setLastRefresh(new Date());
    setLoading(false);
  }, [isFinance, isGod]);

  useEffect(() => {
    void load();
    const interval = setInterval(() => {
      if (document.visibilityState === "visible") void load();
    }, REFRESH_MS);
    const onVis = () => { if (document.visibilityState === "visible") void load(); };
    document.addEventListener("visibilitychange", onVis);
    return () => { clearInterval(interval); document.removeEventListener("visibilitychange", onVis); };
  }, [load]);

  return (
    <ModulePage
      module="dashboard"
      title="Centre opérations"
      subtitle="Console de pilotage mission launch — vue unique des actions critiques"
    >
      {/* Header / refresh */}
      <div className="flex items-center justify-between mb-4">
        <div className="text-xs text-muted-foreground">
          {lastRefresh ? `Dernière mise à jour : ${lastRefresh.toLocaleTimeString()}` : "Chargement…"}
        </div>
        <Button variant="outline" size="sm" onClick={() => void load()} disabled={loading}>
          <RefreshCw className={`w-3.5 h-3.5 mr-1 ${loading ? "animate-spin" : ""}`} />
          Rafraîchir
        </Button>
      </div>

      {/* Launch readiness strip */}
      <section className="mb-6">
        <h2 className="text-sm font-semibold mb-2">Prêt pour le lancement</h2>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2">
          {readiness.map((r) => {
            const meta = STATUS_META[r.status];
            const body = (
              <Card className="p-3 h-full">
                <div className="flex items-start justify-between gap-2 mb-1">
                  <span className="text-[11px] uppercase tracking-wide text-muted-foreground">{r.label}</span>
                  <Badge className={`${meta.cls} text-[10px] border-0`}>{meta.label}</Badge>
                </div>
                <p className="text-xs leading-snug">{r.detail}</p>
              </Card>
            );
            return r.href ? (
              <Link key={r.key} to={r.href} className="block hover:opacity-90 transition">{body}</Link>
            ) : <div key={r.key}>{body}</div>;
          })}
        </div>
        {isGod && masterBalance !== null && (
          <Card className="p-3 mt-2 bg-primary/5">
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted-foreground">Solde master wallet (God Admin uniquement)</span>
              <span className="font-mono font-semibold">
                {new Intl.NumberFormat("fr-FR").format(masterBalance)} GNF
              </span>
            </div>
          </Card>
        )}
      </section>

      {/* Today overview */}
      <section className="mb-6">
        <h2 className="text-sm font-semibold mb-2">Aujourd'hui</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
          {today.filter((c) => !c.hidden).map((c) => {
            const Icon = c.icon;
            const body = (
              <Card className="p-3 h-full">
                <div className="flex items-center justify-between mb-1">
                  <Icon className="w-4 h-4 text-muted-foreground" />
                  {c.value === null && <Badge variant="secondary" className="text-[10px]">Non activé</Badge>}
                </div>
                <p className="text-xl font-semibold">{c.value ?? "—"}</p>
                <p className="text-[11px] text-muted-foreground">{c.label}</p>
              </Card>
            );
            return c.href ? (
              <Link key={c.key} to={c.href} className="block hover:opacity-90 transition">{body}</Link>
            ) : <div key={c.key}>{body}</div>;
          })}
        </div>
      </section>

      {/* Urgent queues */}
      <section className="mb-6 grid grid-cols-1 lg:grid-cols-2 gap-3">
        <UrgentCard
          icon={LifeBuoy}
          title="Support — haute gravité"
          value={urgent.support}
          href="/admin/support"
          actionLabel="Voir tickets"
          empty="Aucune urgence support"
          show
        />
        <UrgentCard
          icon={Bike}
          title="Chauffeurs à approuver"
          value={urgent.pendingDrivers}
          href="/admin/drivers"
          actionLabel="Ouvrir approbations"
          empty="Aucune demande en attente"
          show={isOps}
        />
        <UrgentCard
          icon={Wallet}
          title="Top-ups OM en attente"
          value={urgent.pendingTopups}
          href="/admin/wallet/reconciliation"
          actionLabel="Vérifier (manuel)"
          empty="Aucun top-up en attente"
          hint="Ne pas créditer sans preuve. Vérification opérateur uniquement."
          show={isFinance}
        />
        <UrgentCard
          icon={Coins}
          title="Cashouts chauffeurs"
          value={urgent.pendingCashouts}
          href="/admin/wallet/driver-cashouts"
          actionLabel="Traiter manuellement"
          empty="Aucun cashout en attente"
          hint="Paiement Orange Money manuel uniquement. Aucun virement automatique."
          show={isFinance}
        />
        <UrgentCard
          icon={MapIcon}
          title="Doublons de lieux à fusionner"
          value={urgent.mapDups}
          href="/admin/map/duplicates"
          actionLabel="Réviser"
          empty="Aucun doublon ouvert"
          show={isOps}
        />
        <UrgentCard
          icon={Store}
          title="Boutiques sans localisation"
          value={urgent.storesNoLocation}
          href="/admin/merchants"
          actionLabel="Vérifier marchands"
          empty="Toutes localisées"
          show={isOps}
        />
      </section>

      {/* Quick links */}
      <section className="mb-6">
        <h2 className="text-sm font-semibold mb-2">Liens rapides</h2>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
          <QuickLink to="/admin/drivers" icon={Bike} label="Approbations chauffeurs" />
          <QuickLink to="/admin/map/driver-signals" icon={Activity} label="Signaux chauffeurs" show={isOps} />
          <QuickLink to="/admin/support" icon={LifeBuoy} label="Tickets support" />
          <QuickLink to="/admin/wallet/reconciliation" icon={Wallet} label="Réconciliation OM" show={isFinance} />
          <QuickLink to="/admin/wallet/driver-cashouts" icon={Coins} label="Cashouts chauffeurs" show={isFinance} />
          <QuickLink to="/admin/merchants" icon={Store} label="Marchands" show={isOps} />
          <QuickLink to="/admin/repas" icon={UtensilsCrossed} label="Restaurants Repas" show={isOps} />
          <QuickLink to="/admin/marche" icon={ShoppingBag} label="Marché — boutiques" show={isOps} />
          <QuickLink to="/admin/map/duplicates" icon={MapIcon} label="Doublons lieux" show={isOps} />
          <QuickLink to="/admin/map/routing" icon={MapIcon} label="Routage & ETA" show={isOps} />
          <QuickLink to="/admin/field/pilots" icon={Activity} label="Pilots terrain" show={isOps} />
          <QuickLink to="/admin/settings" icon={Mail} label="SMTP / paramètres" />
        </div>
      </section>

      {/* Safety footer */}
      <Card className="p-3 bg-muted/30">
        <p className="text-[11px] text-muted-foreground leading-relaxed">
          <strong>Règles d'exploitation :</strong> aucun crédit automatique de wallet,
          aucun paiement Orange Money automatique, aucune approbation chauffeur automatique.
          Toute action sensible passe par l'écran dédié. Solde master wallet visible uniquement par le God Admin.
        </p>
      </Card>
    </ModulePage>
  );
}

function UrgentCard({
  icon: Icon, title, value, href, actionLabel, empty, hint, show,
}: {
  icon: typeof Activity; title: string; value: number | null; href: string;
  actionLabel: string; empty: string; hint?: string; show: boolean;
}) {
  if (!show) return null;
  const hasAction = (value ?? 0) > 0;
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3 min-w-0">
          <div className={`w-9 h-9 rounded-lg flex items-center justify-center shrink-0 ${
            hasAction ? "bg-amber-500/10 text-amber-700 dark:text-amber-300" : "bg-muted text-muted-foreground"
          }`}>
            <Icon className="w-4 h-4" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium truncate">{title}</p>
            <p className="text-[11px] text-muted-foreground">
              {value === null ? "Non disponible" : hasAction ? `${value} à traiter` : empty}
            </p>
            {hint && <p className="text-[10px] text-muted-foreground/80 mt-1">{hint}</p>}
          </div>
        </div>
        <Button asChild size="sm" variant={hasAction ? "default" : "outline"}>
          <Link to={href}>{hasAction ? actionLabel : "Voir"}</Link>
        </Button>
      </div>
    </Card>
  );
}

function QuickLink({ to, icon: Icon, label, show = true }: {
  to: string; icon: typeof Activity; label: string; show?: boolean;
}) {
  if (!show) return null;
  return (
    <Link to={to} className="flex items-center gap-2 p-2 rounded-lg border hover:bg-muted/50 transition text-xs">
      <Icon className="w-3.5 h-3.5 text-muted-foreground" />
      <span className="truncate">{label}</span>
    </Link>
  );
}