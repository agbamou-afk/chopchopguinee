import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  Activity, AlertTriangle, Bike, Compass, Info, LifeBuoy, Map as MapIcon,
  RefreshCw, Send, ShoppingBag, Store, UtensilsCrossed, Users2,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import {
  FINANCE_ESCALATION, OPS_UNAVAILABLE_MESSAGE, OpsAttentionItem, OpsOverview,
  OpsOverviewResult, SEVERITY_CLASS, SEVERITY_LABEL, fetchOpsOverview, relativeAge,
} from "@/lib/admin/opsCommandCenter";

const REFRESH_MS = 60_000;

type MetricKey = keyof OpsOverview["snapshot"];

const METRICS: { key: MetricKey; label: string; href: string; icon: typeof Activity }[] = [
  { key: "rides_active", label: "Courses actives", href: "/admin/live", icon: Bike },
  { key: "rides_unassigned", label: "Courses sans chauffeur", href: "/admin/live", icon: AlertTriangle },
  { key: "missions_active", label: "Missions actives", href: "/admin/orders", icon: Activity },
  { key: "envoyer_active", label: "Colis en cours", href: "/admin/orders", icon: Send },
  { key: "repas_active", label: "Commandes Repas", href: "/admin/repas", icon: UtensilsCrossed },
  { key: "marche_active", label: "Commandes Marché", href: "/admin/marche/ops", icon: ShoppingBag },
  { key: "drivers_online", label: "Chauffeurs en ligne (15 min)", href: "/admin/map/driver-signals", icon: Users2 },
  { key: "driver_apps_pending", label: "Candidatures chauffeur", href: "/admin/drivers", icon: Bike },
  { key: "merchant_apps_pending", label: "Boutiques à valider", href: "/admin/merchants", icon: Store },
  { key: "ops_cases_open", label: "Cas opérationnels ouverts", href: "/admin/marche/ops", icon: AlertTriangle },
  { key: "support_open", label: "Tickets support ouverts", href: "/admin/support", icon: LifeBuoy },
  { key: "support_critical", label: "Tickets critiques", href: "/admin/support", icon: AlertTriangle },
];

const SERVICES: { name: string; href: string; icon: typeof Activity; kinds: string[] }[] = [
  { name: "Courses (Moto · Bonbonna · Taxi)", href: "/admin/live", icon: Bike, kinds: ["ride_unassigned"] },
  { name: "Envoyer", href: "/admin/orders", icon: Send, kinds: ["envoyer_stuck", "mission_stuck"] },
  { name: "Repas", href: "/admin/repas", icon: UtensilsCrossed, kinds: ["repas_exception", "repas_case"] },
  { name: "Marché", href: "/admin/marche/ops", icon: ShoppingBag, kinds: ["marche_exception", "marche_case"] },
];

const FIELD_LINKS = [
  { label: "Carte opérationnelle", href: "/admin/live", icon: MapIcon },
  { label: "Lieux & anomalies", href: "/admin/map/places", icon: Compass },
  { label: "Doublons de lieux", href: "/admin/map/duplicates", icon: Compass },
  { label: "Signaux chauffeurs", href: "/admin/map/driver-signals", icon: Activity },
  { label: "Terrain / pilotes", href: "/admin/field/pilots", icon: Users2 },
];

function Metric({ label, value, href, Icon }: {
  label: string; value: number | null | undefined; href: string; Icon: typeof Activity;
}) {
  const unavailable = value === null || value === undefined;
  return (
    <Link to={href} className="block">
      <Card className="p-3 h-full hover:border-primary/50 transition-colors">
        <div className="flex items-start justify-between gap-2">
          <p className="text-[11px] leading-tight text-muted-foreground">{label}</p>
          <Icon className="w-3.5 h-3.5 text-muted-foreground shrink-0" aria-hidden />
        </div>
        {unavailable ? (
          <p className="mt-1.5 text-[12px] text-muted-foreground italic">Indisponible</p>
        ) : (
          <p className="mt-1 text-2xl font-semibold tabular-nums leading-none">{value}</p>
        )}
      </Card>
    </Link>
  );
}

function AttentionRow({ item }: { item: OpsAttentionItem }) {
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 border-b border-border/50 last:border-0">
      <Badge variant="outline" className={`shrink-0 text-[10px] ${SEVERITY_CLASS[item.severity] ?? ""}`}>
        {SEVERITY_LABEL[item.severity] ?? item.severity}
      </Badge>
      <span className="text-[11px] font-mono uppercase tracking-wider text-muted-foreground shrink-0">
        {item.service}
      </span>
      <span className="text-[13px] font-medium min-w-0 truncate">{item.label}</span>
      <span className="text-[11px] font-mono text-muted-foreground">#{item.reference}</span>
      {item.state && <span className="text-[11px] text-muted-foreground">état : {item.state}</span>}
      <span className="text-[11px] text-muted-foreground tabular-nums">depuis {relativeAge(item.since)}</span>
      {item.finance_context && (
        <span className="text-[11px] text-muted-foreground">
          {item.finance_context} · <span className="italic">{FINANCE_ESCALATION}</span>
        </span>
      )}
      <Button asChild size="sm" variant="outline" className="h-6 px-2 text-[11px] ml-auto">
        <Link to={item.href}>Ouvrir</Link>
      </Button>
    </li>
  );
}

export default function OpsCommandCenter() {
  const { role } = useAdminAuth();
  const [data, setData] = useState<OpsOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const res: OpsOverviewResult = await fetchOpsOverview();
    if (res.ok === true) { setData(res.data); setError(null); }
    else { setError(res.error); }
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
    const id = setInterval(() => {
      if (document.visibilityState === "visible") void load();
    }, REFRESH_MS);
    return () => clearInterval(id);
  }, [load]);

  const snap = data?.snapshot;
  const attention = data?.attention ?? [];

  return (
    <div className="space-y-4 max-w-6xl mx-auto">
      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-border/60 pb-2">
        <div className="min-w-0">
          <p className="admin-eyebrow">operations</p>
          <h1 className="text-[18px] font-semibold tracking-tight leading-tight mt-0.5">
            Centre des opérations
          </h1>
          <p className="text-[12px] text-muted-foreground mt-0.5">
            Vue opérationnelle temps réel. Les faits financiers sont en lecture seule.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {data?.generated_at && (
            <span className="text-[11px] text-muted-foreground tabular-nums">
              MAJ {new Date(data.generated_at).toLocaleTimeString("fr-FR")}
            </span>
          )}
          <Button size="sm" variant="outline" className="h-7" onClick={() => void load()} disabled={loading}>
            <RefreshCw className={`w-3.5 h-3.5 mr-1.5 ${loading ? "animate-spin" : ""}`} />
            Actualiser
          </Button>
        </div>
      </div>

      {error && (
        <Card className="p-3 border-destructive/40 bg-destructive/5">
          <p className="text-[13px] text-destructive font-medium">{error}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Aucun chiffre n'est affiché tant que la lecture n'a pas abouti.
          </p>
        </Card>
      )}

      {loading && !data && !error && (
        <p className="text-[13px] text-muted-foreground">Chargement des données opérationnelles…</p>
      )}

      {data && (
        <>
          <section aria-labelledby="ops-snapshot" className="space-y-2">
            <h2 id="ops-snapshot" className="admin-eyebrow">Instantané de service</h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
              {METRICS.map((m) => (
                <Metric key={m.key} label={m.label} value={snap?.[m.key]} href={m.href} Icon={m.icon} />
              ))}
            </div>
          </section>

          <section aria-labelledby="ops-attention" className="space-y-2">
            <h2 id="ops-attention" className="admin-eyebrow">À traiter maintenant</h2>
            <Card className="p-3">
              {attention.length === 0 ? (
                <p className="text-[13px] text-muted-foreground">
                  Aucun élément opérationnel en attente. (0 élément — lecture réussie.)
                </p>
              ) : (
                <ul className="divide-y-0">
                  {attention.map((item) => (
                    <AttentionRow key={`${item.kind}-${item.reference}`} item={item} />
                  ))}
                </ul>
              )}
            </Card>
          </section>

          <section aria-labelledby="ops-services" className="space-y-2">
            <h2 id="ops-services" className="admin-eyebrow">Services</h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {SERVICES.map((s) => {
                const open = attention.filter((a) => s.kinds.includes(a.kind));
                const critical = open.filter((a) => a.severity === "critical").length;
                return (
                  <Card key={s.name} className="p-3">
                    <div className="flex items-center gap-2">
                      <s.icon className="w-4 h-4 text-muted-foreground" aria-hidden />
                      <p className="text-[13px] font-medium min-w-0 truncate">{s.name}</p>
                      <Button asChild size="sm" variant="ghost" className="h-6 px-2 text-[11px] ml-auto">
                        <Link to={s.href}>Ouvrir</Link>
                      </Button>
                    </div>
                    <p className="text-[11px] text-muted-foreground mt-1 tabular-nums">
                      {open.length} exception(s) · {critical} critique(s)
                    </p>
                  </Card>
                );
              })}
            </div>
          </section>

          <section aria-labelledby="ops-supply" className="space-y-2">
            <h2 id="ops-supply" className="admin-eyebrow">Offre & partenaires</h2>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <Metric label="Chauffeurs approuvés" value={snap?.drivers_approved} href="/admin/drivers" Icon={Bike} />
              <Metric label="Candidatures chauffeur" value={snap?.driver_apps_pending} href="/admin/drivers" Icon={Bike} />
              <Metric label="Boutiques à valider" value={snap?.merchant_apps_pending} href="/admin/merchants" Icon={Store} />
              <Metric label="Doublons de lieux" value={snap?.map_duplicates_open} href="/admin/map/duplicates" Icon={Compass} />
            </div>
          </section>

          <section aria-labelledby="ops-field" className="space-y-2">
            <h2 id="ops-field" className="admin-eyebrow">Carte & terrain</h2>
            <div className="flex flex-wrap gap-2">
              {FIELD_LINKS.map((l) => (
                <Button key={l.href} asChild size="sm" variant="outline" className="h-7 text-[12px]">
                  <Link to={l.href}><l.icon className="w-3.5 h-3.5 mr-1.5" />{l.label}</Link>
                </Button>
              ))}
            </div>
          </section>

          {role === "operations_admin" && (
            <Card className="p-3 border-dashed">
              <p className="text-[12px] text-muted-foreground flex items-start gap-2">
                <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" aria-hidden />
                <span>
                  Les états de paiement, règlement et remboursement affichés ici sont un
                  contexte <strong>en lecture seule</strong>. Toute action monétaire relève de
                  la Finance : <em>{FINANCE_ESCALATION}</em>.
                </span>
              </p>
            </Card>
          )}
        </>
      )}

      {!data && !loading && !error && (
        <p className="text-[13px] text-muted-foreground">{OPS_UNAVAILABLE_MESSAGE}</p>
      )}
    </div>
  );
}
