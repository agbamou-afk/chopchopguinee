import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Activity, CheckCircle2, AlertTriangle, Hourglass, Wallet, LifeBuoy,
  Bike, Store, MapPin, ExternalLink, ShieldCheck,
} from "lucide-react";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { supabase } from "@/integrations/supabase/client";
import { DISTRICTS, districtChipClasses, type DistrictMeta } from "@/lib/districts";
import { MISSION_TYPE_SHORT, MISSION_STATE_LABEL, type Mission } from "@/lib/missions/types";
import { needsReview } from "@/lib/payments/review";
import type { PaymentIntent } from "@/lib/payments/types";

/* -------------------------------------------------------------------------- */
/* Helpers                                                                    */
/* -------------------------------------------------------------------------- */

const PILOT_DISTRICTS = ["Kipé", "Dixinn", "Kaloum", "Ratoma", "Matoto"] as const;

const startOfTodayIso = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
};

const ageMin = (iso: string) =>
  Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));

function fmtAge(iso: string) {
  const m = ageMin(iso);
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  return `${h}h${String(m % 60).padStart(2, "0")}`;
}

function districtFromText(text?: string | null): DistrictMeta | null {
  if (!text) return null;
  const lower = text.toLowerCase();
  return DISTRICTS.find((d) => lower.includes(d.name.toLowerCase())) ?? null;
}

type Tone = "ok" | "warn" | "alert" | "muted";
const toneClass: Record<Tone, string> = {
  ok:    "text-emerald-700 dark:text-emerald-400 bg-emerald-500/10 border-emerald-500/30",
  warn:  "text-amber-700 dark:text-amber-400 bg-amber-500/10 border-amber-500/30",
  alert: "text-destructive bg-destructive/10 border-destructive/30",
  muted: "text-muted-foreground bg-muted/40 border-border/60",
};

/* -------------------------------------------------------------------------- */
/* Data hooks                                                                 */
/* -------------------------------------------------------------------------- */

const REFRESH_MS = 60_000;

function useMissions() {
  return useQuery({
    queryKey: ["pilot-cc", "missions"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const { data, error } = await (supabase as any)
        .from("missions")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(60);
      if (error) throw error;
      return (data ?? []) as Mission[];
    },
  });
}

function usePaymentIntents() {
  return useQuery({
    queryKey: ["pilot-cc", "payment_intents"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const { data, error } = await (supabase as any)
        .from("payment_intents")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(80);
      if (error) throw error;
      return (data ?? []) as PaymentIntent[];
    },
  });
}

interface CourierRow {
  user_id: string; presence: string; status: string;
  capabilities: string[]; current_operating_district: string | null;
  last_seen_district: string | null; preferred_district: string | null;
  last_seen_at: string | null;
}

function useCouriers() {
  return useQuery({
    queryKey: ["pilot-cc", "couriers"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("driver_profiles")
        .select("user_id,presence,status,capabilities,current_operating_district,last_seen_district,preferred_district,last_seen_at")
        .order("last_seen_at", { ascending: false, nullsFirst: false })
        .limit(40);
      if (error) throw error;
      return (data ?? []) as CourierRow[];
    },
  });
}

interface RestaurantRow {
  id: string; name: string; district: string | null;
  is_open: boolean; delivery_available: boolean; status: string; updated_at: string;
}

function useRestaurants() {
  return useQuery({
    queryKey: ["pilot-cc", "restaurants"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("food_restaurants")
        .select("id,name,district,is_open,delivery_available,status,updated_at")
        .eq("status", "active")
        .order("updated_at", { ascending: false })
        .limit(40);
      if (error) throw error;
      return (data ?? []) as RestaurantRow[];
    },
  });
}

interface StoreRow {
  id: string; name: string; district: string | null;
  delivery_available: boolean; status: string; updated_at: string;
}

function useStores() {
  return useQuery({
    queryKey: ["pilot-cc", "stores"],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("merchant_stores")
        .select("id,name,district,delivery_available,status,updated_at")
        .eq("status", "active")
        .order("updated_at", { ascending: false })
        .limit(40);
      if (error) throw error;
      return (data ?? []) as StoreRow[];
    },
  });
}

/* -------------------------------------------------------------------------- */
/* Tiny UI primitives                                                         */
/* -------------------------------------------------------------------------- */

function PulseStat({
  label, value, tone = "muted", icon: Icon, sub,
}: {
  label: string;
  value: string | number;
  tone?: Tone;
  icon: React.ComponentType<{ className?: string }>;
  sub?: string;
}) {
  return (
    <Card className={`p-3 border ${toneClass[tone]} flex flex-col gap-1`}>
      <div className="flex items-center gap-1.5 text-[10px] font-mono uppercase tracking-wider opacity-80">
        <Icon className="w-3 h-3" />
        {label}
      </div>
      <div className="text-2xl font-semibold tabular-nums leading-none">{value}</div>
      {sub && <div className="text-[11px] opacity-70 leading-tight">{sub}</div>}
    </Card>
  );
}

function SectionCard({
  title, eyebrow, action, children,
}: {
  title: string;
  eyebrow?: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-end justify-between gap-3">
        <div>
          {eyebrow && (
            <p className="font-mono text-[10px] tracking-[0.16em] uppercase text-muted-foreground/70">
              {eyebrow}
            </p>
          )}
          <h2 className="text-sm font-semibold tracking-tight">{title}</h2>
        </div>
        {action}
      </div>
      {children}
    </Card>
  );
}

function EmptyRow({ children }: { children: React.ReactNode }) {
  return (
    <div className="text-[12px] text-muted-foreground italic px-2 py-3 border border-dashed border-border/60 rounded">
      {children}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

export default function PilotCommandCenter() {
  const { can } = useAdminAuth();
  const canSeePayments = can("payments");

  const missionsQ = useMissions();
  const paymentsQ = usePaymentIntents();
  const couriersQ = useCouriers();
  const restaurantsQ = useRestaurants();
  const storesQ = useStores();

  const missions = missionsQ.data ?? [];
  const payments = paymentsQ.data ?? [];
  const couriers = couriersQ.data ?? [];
  const restaurants = restaurantsQ.data ?? [];
  const stores = storesQ.data ?? [];

  const todayIso = startOfTodayIso();

  /* ---------------- Derived metrics ---------------- */

  const activeMissions = missions.filter(
    (m) => m.state !== "delivered" && m.state !== "failed",
  ).sort(
    // Triage: oldest active first (most urgent at top)
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
  );
  const completedToday = missions.filter(
    (m) => m.state === "delivered" && m.updated_at >= todayIso,
  );
  const failedToday = missions.filter(
    (m) => m.state === "failed" && m.updated_at >= todayIso,
  );

  const pendingPayments = payments.filter(
    (p) => p.state === "pending" || p.state === "processing",
  );
  const reviewNeeded = payments.filter((p) => needsReview(p, []));
  const confirmedToday = payments.filter(
    (p) => p.state === "confirmed" && p.updated_at >= todayIso,
  );
  const failedExpired = payments.filter(
    (p) => p.state === "failed" || p.state === "expired",
  );

  // `presence` is best-effort and may be stale — surface as "présence en ligne"
  // with a partial-data sub-label rather than a hard "active courier" count.
  const presenceOnline = couriers.filter(
    (c) => c.presence === "online" || c.presence === "on_trip",
  );
  // Restaurants expose `is_open`. merchant_stores has no opening-state column —
  // we therefore only count restaurants here and mark merchants as "actifs"
  // separately, to avoid implying we know whether stores are open right now.
  const openRestaurants = restaurants.filter((r) => r.is_open);
  const activeMerchantsTotal = restaurants.length + stores.length;

  /* ---------------- Go / No-Go ---------------- */

  const longPending = pendingPayments.filter((p) => ageMin(p.created_at) > 30);
  // Data-source availability — drives partial-data warnings, never inflates green.
  const missingSources: string[] = ["File support (à connecter)"];
  if (!canSeePayments) missingSources.push("Détails paiements (permission requise)");
  // Courier presence is best-effort; treat it as a partial source whenever
  // active missions exist but no courier reports presence.
  const presenceUnreliable =
    activeMissions.length > 0 && presenceOnline.length === 0;
  if (presenceUnreliable) missingSources.push("Présence coursier (à connecter)");

  let healthTone: Tone = "ok";
  const healthNotes: string[] = [];

  if (failedToday.length > 5) {
    healthTone = "alert";
    healthNotes.push(`${failedToday.length} missions échouées aujourd'hui`);
  }
  if (canSeePayments && reviewNeeded.length > 0) {
    healthTone = "alert";
    healthNotes.push(`${reviewNeeded.length} paiement(s) à vérifier`);
  }
  if (presenceUnreliable) {
    // Active missions but no online courier → at minimum a yellow warning.
    if (healthTone !== "alert") healthTone = "warn";
    healthNotes.push("Missions actives mais aucune présence coursier en ligne");
  }
  if (
    healthTone !== "alert" &&
    canSeePayments &&
    (longPending.length > 0 || pendingPayments.length > 0)
  ) {
    healthTone = "warn";
    if (longPending.length > 0)
      healthNotes.push(`${longPending.length} paiement(s) en attente > 30 min`);
    else healthNotes.push(`${pendingPayments.length} paiement(s) en attente`);
  }

  // Honesty rule: never claim full green while critical sources are missing.
  const healthPartial = missingSources.length > 0;
  if (healthTone === "ok" && healthPartial) healthTone = "muted";

  const healthLabel =
    healthTone === "alert"
      ? "Rouge — action requise"
      : healthTone === "warn"
      ? "Jaune — surveiller"
      : healthTone === "ok"
      ? "Vert — opérer normalement"
      : "Partiel — données à connecter";

  return (
    <ModulePage
      module="dashboard"
      title="Pilot Command"
      subtitle="Lecture seule · cockpit opérationnel du pilote CHOPCHOP"
      actions={
        <Badge variant="outline" className="font-mono text-[10px] tracking-wider uppercase">
          Phase B · read-only
        </Badge>
      }
    >
      <div className="space-y-5">
        {/* 1. Today's Pulse */}
        <SectionCard title="Pouls du jour" eyebrow="01 · pulse">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <PulseStat label="Missions actives" value={activeMissions.length} icon={Activity}
              tone={activeMissions.length > 30 ? "warn" : "ok"} />
            <PulseStat label="Livrées aujourd'hui" value={completedToday.length} icon={CheckCircle2} tone="ok" />
            <PulseStat label="Échecs aujourd'hui" value={failedToday.length} icon={AlertTriangle}
              tone={failedToday.length > 5 ? "alert" : failedToday.length > 0 ? "warn" : "muted"} />
            <PulseStat label="Paiements en attente" value={canSeePayments ? pendingPayments.length : "—"} icon={Hourglass}
              tone={canSeePayments && longPending.length > 0 ? "warn" : "muted"}
              sub={canSeePayments ? undefined : "Permission paiements requise"} />
            <PulseStat label="Paiements à vérifier" value={canSeePayments ? reviewNeeded.length : "—"} icon={Wallet}
              tone={canSeePayments && reviewNeeded.length > 0 ? "alert" : "muted"}
              sub={canSeePayments ? undefined : "Permission paiements requise"} />
            <PulseStat label="Support" value="—" icon={LifeBuoy} tone="muted" sub="À connecter" />
            <PulseStat
              label="Présence coursier"
              value={presenceOnline.length}
              icon={Bike}
              tone={presenceUnreliable ? "warn" : "muted"}
              sub="Best-effort · partiel"
            />
            <PulseStat
              label="Marchands actifs"
              value={activeMerchantsTotal}
              icon={Store}
              tone={activeMerchantsTotal === 0 ? "warn" : "ok"}
              sub={`${openRestaurants.length} resto ouverts · stores sans état`}
            />
          </div>
        </SectionCard>

        {/* 2. Live missions */}
        <SectionCard
          title="Missions en cours"
          eyebrow="02 · live missions"
          action={<Badge variant="outline" className="text-[10px]">{activeMissions.length}</Badge>}
        >
          {missionsQ.isLoading ? (
            <EmptyRow>Chargement…</EmptyRow>
          ) : activeMissions.length === 0 ? (
            <EmptyRow>Aucune mission active.</EmptyRow>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-[12px]">
                <thead className="text-[10px] font-mono uppercase tracking-wider text-muted-foreground/70">
                  <tr className="border-b border-border/60">
                    <th className="text-left py-1.5 pr-2">Type</th>
                    <th className="text-left py-1.5 pr-2">Trajet</th>
                    <th className="text-left py-1.5 pr-2">État</th>
                    <th className="text-left py-1.5 pr-2">Coursier</th>
                    <th className="text-right py-1.5 pl-2">Âge</th>
                  </tr>
                </thead>
                <tbody>
                  {activeMissions.slice(0, 20).map((m) => {
                    const fromD = districtFromText(m.pickup_address);
                    const toD = districtFromText(m.dropoff_address);
                    const issue = !!m.issue_reason;
                    return (
                      <tr key={m.id} className="border-b border-border/30 hover:bg-muted/30">
                        <td className="py-1.5 pr-2 whitespace-nowrap">{MISSION_TYPE_SHORT[m.type]}</td>
                        <td className="py-1.5 pr-2 whitespace-nowrap">
                          <span className={fromD ? districtChipClasses(fromD.tone) : "text-muted-foreground"}>
                            {fromD?.name ?? "—"}
                          </span>
                          <span className="mx-1 text-muted-foreground/60">→</span>
                          <span className={toD ? districtChipClasses(toD.tone) : "text-muted-foreground"}>
                            {toD?.name ?? "—"}
                          </span>
                        </td>
                        <td className="py-1.5 pr-2 whitespace-nowrap">
                          {issue ? (
                            <span className="inline-flex items-center gap-1 text-destructive">
                              <AlertTriangle className="w-3 h-3" /> Problème
                            </span>
                          ) : (
                            <span className="text-muted-foreground">{MISSION_STATE_LABEL[m.state]}</span>
                          )}
                        </td>
                        <td className="py-1.5 pr-2 font-mono text-[11px] text-muted-foreground">
                          {m.courier_id ? `${m.courier_id.slice(0, 6)}…` : "—"}
                        </td>
                        <td className="py-1.5 pl-2 text-right tabular-nums text-muted-foreground">{fmtAge(m.created_at)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </SectionCard>

        {/* 3. Payments review */}
        <SectionCard
          title="Paiements — résumé"
          eyebrow="03 · payments review"
          action={
            canSeePayments && (
              <Button asChild variant="outline" size="sm" className="h-7 text-[11px]">
                <Link to="/admin/payments">
                  Voir réconciliation paiements <ExternalLink className="w-3 h-3 ml-1" />
                </Link>
              </Button>
            )
          }
        >
          {!canSeePayments ? (
            <EmptyRow>Votre rôle ne dispose pas de la permission paiements.</EmptyRow>
          ) : (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
              <PulseStat label="En attente" value={pendingPayments.length} icon={Hourglass}
                tone={longPending.length > 0 ? "warn" : "muted"} />
              <PulseStat label="Échoués / expirés" value={failedExpired.length} icon={AlertTriangle}
                tone={failedExpired.length > 0 ? "warn" : "muted"} />
              <PulseStat label="À vérifier" value={reviewNeeded.length} icon={Wallet}
                tone={reviewNeeded.length > 0 ? "alert" : "muted"} />
              <PulseStat label="Confirmés aujourd'hui" value={confirmedToday.length} icon={CheckCircle2} tone="ok" />
            </div>
          )}
        </SectionCard>

        {/* 4. Support */}
        <SectionCard title="Support / Incidents" eyebrow="04 · support">
          <EmptyRow>File support à connecter — pas de table dédiée pour l'instant.</EmptyRow>
        </SectionCard>

        {/* 5. Merchant watch */}
        <SectionCard title="Marchands à surveiller" eyebrow="05 · merchant watch">
          {restaurantsQ.isLoading || storesQ.isLoading ? (
            <EmptyRow>Chargement…</EmptyRow>
          ) : restaurants.length + stores.length === 0 ? (
            <EmptyRow>Aucun marchand actif.</EmptyRow>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
              {restaurants.slice(0, 6).map((r) => {
                const d = r.district ? districtFromText(r.district) : null;
                return (
                  <div key={r.id} className="flex items-center gap-2 p-2 border border-border/60 rounded text-[12px]">
                    <span className="font-mono text-[10px] uppercase text-muted-foreground/70">Repas</span>
                    <span className="font-medium truncate flex-1">{r.name}</span>
                    {d && <span className={districtChipClasses(d.tone)}>{d.name}</span>}
                    <span className={r.is_open ? "text-emerald-600 text-[11px]" : "text-muted-foreground text-[11px]"}>
                      {r.is_open ? "Ouvert" : "Fermé"}
                    </span>
                  </div>
                );
              })}
              {stores.slice(0, 6).map((s) => {
                const d = s.district ? districtFromText(s.district) : null;
                return (
                  <div key={s.id} className="flex items-center gap-2 p-2 border border-border/60 rounded text-[12px]">
                    <span className="font-mono text-[10px] uppercase text-muted-foreground/70">Marché</span>
                    <span className="font-medium truncate flex-1">{s.name}</span>
                    {d && <span className={districtChipClasses(d.tone)}>{d.name}</span>}
                    <span className={s.delivery_available ? "text-emerald-600 text-[11px]" : "text-muted-foreground text-[11px]"}>
                      {s.delivery_available ? "Livraison" : "Retrait"}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </SectionCard>

        {/* 6. Courier watch */}
        <SectionCard title="Coursiers à surveiller" eyebrow="06 · courier watch">
          {couriersQ.isLoading ? (
            <EmptyRow>Chargement…</EmptyRow>
          ) : couriers.length === 0 ? (
            <EmptyRow>Aucun coursier enregistré.</EmptyRow>
          ) : (
            <>
              <p className="text-[10px] font-mono uppercase tracking-wider text-muted-foreground/70 mb-1">
                Présence temps réel partielle · basée sur dernière connexion
              </p>
              <div className="overflow-x-auto">
                <table className="w-full text-[12px]">
                  <thead className="text-[10px] font-mono uppercase tracking-wider text-muted-foreground/70">
                    <tr className="border-b border-border/60">
                      <th className="text-left py-1.5 pr-2">Coursier</th>
                      <th className="text-left py-1.5 pr-2">Présence</th>
                      <th className="text-left py-1.5 pr-2">District</th>
                      <th className="text-left py-1.5 pr-2">Capacités</th>
                      <th className="text-right py-1.5 pl-2">Vu</th>
                    </tr>
                  </thead>
                  <tbody>
                    {couriers.slice(0, 12).map((c) => {
                      const d = districtFromText(
                        c.current_operating_district ?? c.last_seen_district ?? c.preferred_district,
                      );
                      const online = c.presence === "online" || c.presence === "on_trip";
                      return (
                        <tr key={c.user_id} className="border-b border-border/30">
                          <td className="py-1.5 pr-2 font-mono text-[11px] text-muted-foreground">
                            {c.user_id.slice(0, 8)}…
                          </td>
                          <td className="py-1.5 pr-2">
                            <span className={online ? "text-emerald-600" : "text-muted-foreground"}>
                              {c.presence}
                            </span>
                          </td>
                          <td className="py-1.5 pr-2">
                            {d ? <span className={districtChipClasses(d.tone)}>{d.name}</span> : <span className="text-muted-foreground">—</span>}
                          </td>
                          <td className="py-1.5 pr-2 text-[11px] text-muted-foreground truncate max-w-[200px]">
                            {(c.capabilities ?? []).join(", ") || "—"}
                          </td>
                          <td className="py-1.5 pl-2 text-right text-muted-foreground tabular-nums">
                            {c.last_seen_at ? fmtAge(c.last_seen_at) : "—"}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </SectionCard>

        {/* 7. District activity */}
        <SectionCard title="Activité par district" eyebrow="07 · districts">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            {PILOT_DISTRICTS.map((name) => {
              const meta = DISTRICTS.find((d) => d.name === name);
              if (!meta) return null;
              const inDistrict = (text?: string | null) =>
                !!text && text.toLowerCase().includes(name.toLowerCase());
              const dActive = activeMissions.filter(
                (m) => inDistrict(m.pickup_address) || inDistrict(m.dropoff_address),
              );
              const dCompleted = completedToday.filter(
                (m) => inDistrict(m.pickup_address) || inDistrict(m.dropoff_address),
              );
              const dFailed = failedToday.filter(
                (m) => inDistrict(m.pickup_address) || inDistrict(m.dropoff_address),
              );
              const dCouriers = presenceOnline.filter((c) =>
                [c.current_operating_district, c.last_seen_district, c.preferred_district].some(
                  (x) => x?.toLowerCase() === name.toLowerCase(),
                ),
              );
              const dMerchants =
                restaurants.filter((r) => r.district?.toLowerCase() === name.toLowerCase() && r.is_open).length +
                stores.filter((s) => s.district?.toLowerCase() === name.toLowerCase()).length;

              return (
                <Card key={name} className="p-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className={`${districtChipClasses(meta.tone)} text-[11px]`}>
                      <MapPin className="w-3 h-3 inline mr-1" />{name}
                    </span>
                    <span className="font-mono text-[10px] text-muted-foreground/70 uppercase">
                      {meta.status}
                    </span>
                  </div>
                  <div className="grid grid-cols-3 gap-1 text-[11px]">
                    <div><div className="text-muted-foreground">Actives</div><div className="font-semibold tabular-nums">{dActive.length}</div></div>
                    <div><div className="text-muted-foreground">Livrées</div><div className="font-semibold tabular-nums">{dCompleted.length}</div></div>
                    <div><div className="text-muted-foreground">Échecs</div><div className="font-semibold tabular-nums">{dFailed.length}</div></div>
                    <div><div className="text-muted-foreground">Coursiers</div><div className="font-semibold tabular-nums">{dCouriers.length}</div></div>
                    <div><div className="text-muted-foreground">Marchands</div><div className="font-semibold tabular-nums">{dMerchants}</div></div>
                    <div><div className="text-muted-foreground">Support</div><div className="font-semibold text-muted-foreground/60">—</div></div>
                  </div>
                </Card>
              );
            })}
          </div>
        </SectionCard>

        {/* 8. Go / No-Go health */}
        <SectionCard
          title="Santé opérationnelle — Go / No-Go"
          eyebrow="08 · health"
          action={
            <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded border text-[11px] font-medium ${toneClass[healthTone]}`}>
              <ShieldCheck className="w-3 h-3" />
              {healthLabel}
            </span>
          }
        >
          <ul className="text-[12px] space-y-1">
            {healthNotes.length === 0 ? (
              <li className="text-muted-foreground">Aucun signal critique détecté à partir des sources connectées.</li>
            ) : (
              healthNotes.map((n, i) => (
                <li key={i} className="flex items-start gap-2">
                  <span className={healthTone === "alert" ? "text-destructive" : "text-amber-600"}>•</span>
                  <span>{n}</span>
                </li>
              ))
            )}
          </ul>
          {healthPartial && (
            <div className="border-t border-border/40 pt-2 mt-2 space-y-0.5">
              <p className="text-[10px] font-mono uppercase tracking-wider text-muted-foreground/70">
                Sources manquantes
              </p>
              <ul className="text-[11px] text-muted-foreground italic">
                {missingSources.map((s) => (
                  <li key={s}>· {s}</li>
                ))}
              </ul>
            </div>
          )}
        </SectionCard>
      </div>
    </ModulePage>
  );
}