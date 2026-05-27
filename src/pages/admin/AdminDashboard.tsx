import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ModulePage } from "@/components/admin/ModulePage";
import { Button } from "@/components/ui/button";
import {
  LifeBuoy, Wallet, Activity, ArrowRight, ShieldCheck, AlertTriangle,
  Hourglass, CheckCircle2, Store, Bike,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

const REFRESH_MS = 60_000;

function startOfTodayIso() {
  const d = new Date(); d.setHours(0, 0, 0, 0); return d.toISOString();
}

/* ------------------ real-data hooks ------------------ */

function useOpenSupport() {
  return useQuery({
    queryKey: ["admin-home", "support"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const { data, error } = await (supabase as any)
        .from("support_issues")
        .select("id,status,severity")
        .in("status", ["open", "in_review", "escalated"]);
      if (error) throw error;
      const rows = (data ?? []) as { status: string; severity: string }[];
      return {
        open: rows.filter((r) => r.status === "open").length,
        in_review: rows.filter((r) => r.status === "in_review").length,
        escalated: rows.filter((r) => r.status === "escalated").length,
        critical: rows.filter((r) => r.severity === "critical" || r.severity === "high").length,
        total: rows.length,
      };
    },
  });
}

function usePaymentsSummary() {
  return useQuery({
    queryKey: ["admin-home", "payments"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const since = startOfTodayIso();
      const [pending, processing, failed] = await Promise.all([
        (supabase as any).from("payment_intents").select("id", { count: "exact", head: true }).eq("state", "pending"),
        (supabase as any).from("payment_intents").select("id", { count: "exact", head: true }).eq("state", "processing"),
        (supabase as any).from("payment_intents").select("id", { count: "exact", head: true }).eq("state", "failed").gte("created_at", since),
      ]);
      return {
        pending: pending.count ?? 0,
        processing: processing.count ?? 0,
        failed_today: failed.count ?? 0,
      };
    },
  });
}

function useMissionsSummary() {
  return useQuery({
    queryKey: ["admin-home", "missions"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const since = startOfTodayIso();
      const ACTIVE = ["assigned","heading_to_pickup","arrived_pickup","picked_up","heading_to_dropoff","arrived_dropoff"];
      const [active, delivered, failed] = await Promise.all([
        (supabase as any).from("missions").select("id", { count: "exact", head: true }).in("state", ACTIVE),
        (supabase as any).from("missions").select("id", { count: "exact", head: true }).eq("state", "delivered").gte("created_at", since),
        (supabase as any).from("missions").select("id", { count: "exact", head: true }).eq("state", "failed").gte("created_at", since),
      ]);
      return {
        active: active.count ?? 0,
        delivered_today: delivered.count ?? 0,
        failed_today: failed.count ?? 0,
      };
    },
  });
}

function useOperationsSummary() {
  return useQuery({
    queryKey: ["admin-home", "ops"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const [restaurants, couriersOnline, driversPending] = await Promise.all([
        (supabase as any).from("food_restaurants").select("id", { count: "exact", head: true }).eq("status", "active"),
        (supabase as any).from("driver_profiles").select("user_id", { count: "exact", head: true }).eq("presence", "online"),
        (supabase as any).from("driver_applications").select("id", { count: "exact", head: true }).eq("decision", "pending"),
      ]);
      return {
        restaurants_active: restaurants.count ?? 0,
        couriers_online: couriersOnline.count ?? 0,
        drivers_pending: driversPending.count ?? 0,
      };
    },
  });
}

/* ------------------ UI primitives ------------------ */

function MetricCell({
  label, value, loading, error, tone = "default",
}: {
  label: string;
  value?: number | string;
  loading?: boolean;
  error?: boolean;
  tone?: "default" | "ok" | "warn" | "alert";
}) {
  const toneClass =
    tone === "ok" ? "text-emerald-700 dark:text-emerald-400"
    : tone === "warn" ? "text-amber-700 dark:text-amber-400"
    : tone === "alert" ? "text-destructive"
    : "text-foreground";
  return (
    <div className="flex flex-col gap-0.5">
      <span className="admin-eyebrow truncate">{label}</span>
      <span className={`text-[20px] font-semibold tabular-nums leading-none ${toneClass}`}>
        {loading ? "…" : error ? <span className="text-muted-foreground text-[13px]">À connecter</span> : value ?? 0}
      </span>
    </div>
  );
}

function SectionCard({
  title, icon: Icon, to, ctaLabel, children,
}: {
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  to: string;
  ctaLabel: string;
  children: React.ReactNode;
}) {
  return (
    <div className="admin-card p-4 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="admin-eyebrow flex items-center gap-1.5">
          <Icon className="w-3 h-3" /> {title}
        </h2>
        <Link to={to} className="text-[11px] font-mono text-primary hover:underline inline-flex items-center gap-1">
          {ctaLabel} <ArrowRight className="w-3 h-3" />
        </Link>
      </div>
      {children}
    </div>
  );
}

/* ------------------ Page ------------------ */

export default function AdminDashboard() {
  const support = useOpenSupport();
  const payments = usePaymentsSummary();
  const missions = useMissionsSummary();
  const ops = useOperationsSummary();

  return (
    <ModulePage module="dashboard" title="Tableau de bord" subtitle="Vue opérationnelle CHOPCHOP — données en direct">
      {/* Pilot CTA */}
      <div className="admin-card p-4 flex items-center justify-between gap-3 border-primary/30">
        <div className="min-w-0">
          <div className="admin-eyebrow flex items-center gap-1.5 mb-1">
            <ShieldCheck className="w-3 h-3" /> Pilot Command Center
          </div>
          <p className="text-[13px] text-muted-foreground">
            État Go/No-Go, districts, missions, paiements et support consolidés.
          </p>
        </div>
        <Link to="/admin/pilot-command">
          <Button size="sm" className="gradient-primary shrink-0">
            Ouvrir <ArrowRight className="w-3.5 h-3.5 ml-1" />
          </Button>
        </Link>
      </div>

      <div className="grid md:grid-cols-2 gap-3">
        {/* Support */}
        <SectionCard title="Support" icon={LifeBuoy} to="/admin/support" ctaLabel="Ouvrir support">
          <div className="grid grid-cols-3 gap-3">
            <MetricCell label="Ouverts" value={support.data?.open} loading={support.isLoading} error={support.isError} />
            <MetricCell label="En revue" value={support.data?.in_review} loading={support.isLoading} error={support.isError} tone="warn" />
            <MetricCell label="Escaladés" value={support.data?.escalated} loading={support.isLoading} error={support.isError} tone="alert" />
          </div>
          {support.data && support.data.total === 0 && (
            <p className="text-[12px] text-muted-foreground">Aucun problème support ouvert.</p>
          )}
        </SectionCard>

        {/* Payments */}
        <SectionCard title="Paiements" icon={Wallet} to="/admin/payments" ctaLabel="Réconciliation">
          <div className="grid grid-cols-3 gap-3">
            <MetricCell label="En attente" value={payments.data?.pending} loading={payments.isLoading} error={payments.isError} tone="warn" />
            <MetricCell label="En cours" value={payments.data?.processing} loading={payments.isLoading} error={payments.isError} />
            <MetricCell label="Échecs (auj.)" value={payments.data?.failed_today} loading={payments.isLoading} error={payments.isError} tone="alert" />
          </div>
          {payments.data && payments.data.pending + payments.data.processing + payments.data.failed_today === 0 && (
            <p className="text-[12px] text-muted-foreground">Aucun paiement à vérifier.</p>
          )}
        </SectionCard>

        {/* Missions */}
        <SectionCard title="Missions" icon={Activity} to="/admin/pilot-command" ctaLabel="Voir live ops">
          <div className="grid grid-cols-3 gap-3">
            <MetricCell label="Actives" value={missions.data?.active} loading={missions.isLoading} error={missions.isError} />
            <MetricCell label="Livrées (auj.)" value={missions.data?.delivered_today} loading={missions.isLoading} error={missions.isError} tone="ok" />
            <MetricCell label="Échecs (auj.)" value={missions.data?.failed_today} loading={missions.isLoading} error={missions.isError} tone="alert" />
          </div>
          {missions.data && missions.data.active === 0 && (
            <p className="text-[12px] text-muted-foreground">Aucune mission active.</p>
          )}
        </SectionCard>

        {/* Operations */}
        <SectionCard title="Opérations terrain" icon={Store} to="/admin/drivers" ctaLabel="Chauffeurs">
          <div className="grid grid-cols-3 gap-3">
            <MetricCell label="Restos actifs" value={ops.data?.restaurants_active} loading={ops.isLoading} error={ops.isError} />
            <MetricCell label="Coursiers en ligne" value={ops.data?.couriers_online} loading={ops.isLoading} error={ops.isError} tone="ok" />
            <MetricCell label="Demandes chauffeur" value={ops.data?.drivers_pending} loading={ops.isLoading} error={ops.isError} tone="warn" />
          </div>
        </SectionCard>
      </div>

      {/* Connections to do */}
      <div className="admin-card p-4">
        <h2 className="admin-eyebrow mb-2">À connecter</h2>
        <ul className="text-[12px] text-muted-foreground space-y-1">
          <li>• Statut webhooks providers (paiements) — voir <Link to="/admin/payments" className="text-primary hover:underline">/admin/payments</Link></li>
          <li>• Vérification domaine email <span className="font-mono">notify.chopchopguinee.com</span> (DNS en attente)</li>
          <li>• SMS / Twilio non configuré — OTP téléphone désactivé</li>
          <li>• Statut système temps réel (à brancher sur health-checks)</li>
        </ul>
      </div>
    </ModulePage>
  );
}
