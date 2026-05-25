import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription,
} from "@/components/ui/sheet";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { LifeBuoy, AlertTriangle, CheckCircle2, Clock, ExternalLink } from "lucide-react";
import { toast } from "sonner";
import {
  listAdminIssues,
  updateIssueStatus,
  updateIssueSeverity,
  assignIssueRole,
  resolveIssue,
  escalateIssue,
  type SupportIssue,
} from "@/lib/support/issues";
import {
  ISSUE_STATUSES, ISSUE_STATUS_LABEL, ISSUE_STATUS_TONE,
  ISSUE_TYPES, ISSUE_TYPE_LABEL,
  ISSUE_SEVERITIES, ISSUE_SEVERITY_LABEL, ISSUE_SEVERITY_TONE,
  ISSUE_ROLES, ISSUE_ROLE_LABEL,
  type IssueStatus, type IssueType, type IssueSeverity, type IssueRole,
} from "@/lib/support/constants";
import { DISTRICTS } from "@/lib/districts";

const toneClass: Record<"ok"|"warn"|"alert"|"muted", string> = {
  ok:    "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-500/30",
  warn:  "bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/30",
  alert: "bg-destructive/10 text-destructive border-destructive/30",
  muted: "bg-muted text-muted-foreground border-border/60",
};

function StatusChip({ status }: { status: IssueStatus }) {
  return (
    <span className={`text-[11px] px-2 py-0.5 rounded-full border ${toneClass[ISSUE_STATUS_TONE[status]]}`}>
      {ISSUE_STATUS_LABEL[status]}
    </span>
  );
}
function SeverityChip({ severity }: { severity: IssueSeverity }) {
  return (
    <span className={`text-[11px] px-2 py-0.5 rounded-full border ${toneClass[ISSUE_SEVERITY_TONE[severity]]}`}>
      {ISSUE_SEVERITY_LABEL[severity]}
    </span>
  );
}

function fmtWhen(iso: string) {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (min < 60) return `il y a ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `il y a ${h} h`;
  return new Date(iso).toLocaleDateString("fr-FR");
}

export default function SupportAdmin() {
  const qc = useQueryClient();
  const [status, setStatus] = useState<IssueStatus | "all">("all");
  const [type, setType] = useState<IssueType | "all">("all");
  const [severity, setSeverity] = useState<IssueSeverity | "all">("all");
  const [role, setRole] = useState<IssueRole | "all">("all");
  const [district, setDistrict] = useState<string>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const issuesQ = useQuery({
    queryKey: ["support_issues", { status, type, severity, role, district }],
    refetchInterval: 60_000,
    queryFn: () => listAdminIssues({
      status, type, severity, district,
      assignedRole: role,
      limit: 200,
    }),
  });

  const issues = issuesQ.data ?? [];
  const selected = useMemo(
    () => issues.find((i) => i.id === selectedId) ?? null,
    [issues, selectedId],
  );

  const stats = useMemo(() => {
    const open = issues.filter((i) => i.status === "open" || i.status === "in_review").length;
    const critical = issues.filter((i) => i.severity === "critical" && i.status !== "resolved" && i.status !== "cancelled").length;
    const resolved24 = issues.filter((i) =>
      i.resolved_at && Date.now() - new Date(i.resolved_at).getTime() < 24 * 3600 * 1000,
    ).length;
    const escalated = issues.filter((i) => i.status === "escalated").length;
    return { open, critical, resolved24, escalated };
  }, [issues]);

  const refresh = () => qc.invalidateQueries({ queryKey: ["support_issues"] });

  const onChangeStatus = async (id: string, next: IssueStatus) => {
    try {
      await updateIssueStatus(id, next);
      toast.success(`Statut → ${ISSUE_STATUS_LABEL[next]}`);
      refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action refusée");
    }
  };
  const onChangeSeverity = async (id: string, next: IssueSeverity) => {
    try { await updateIssueSeverity(id, next); toast.success(`Sévérité → ${ISSUE_SEVERITY_LABEL[next]}`); refresh(); }
    catch (e) { toast.error(e instanceof Error ? e.message : "Action refusée"); }
  };
  const onChangeRole = async (id: string, next: IssueRole) => {
    try { await assignIssueRole(id, next); toast.success(`Assigné → ${ISSUE_ROLE_LABEL[next]}`); refresh(); }
    catch (e) { toast.error(e instanceof Error ? e.message : "Action refusée"); }
  };
  const onResolve = async (id: string) => {
    try { await resolveIssue(id); toast.success("Issue résolue"); refresh(); }
    catch (e) { toast.error(e instanceof Error ? e.message : "Action refusée"); }
  };
  const onEscalate = async (id: string) => {
    try { await escalateIssue(id); toast.success("Issue escaladée"); refresh(); }
    catch (e) { toast.error(e instanceof Error ? e.message : "Action refusée"); }
  };

  return (
    <ModulePage module="support" title="Support / Issues" subtitle="Journal opérationnel des incidents pilote">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
        <StatCard label="Ouverts" value={stats.open} icon={LifeBuoy} tone="warn" />
        <StatCard label="Critiques actifs" value={stats.critical} icon={AlertTriangle} tone="alert" />
        <StatCard label="Résolus (24h)" value={stats.resolved24} icon={CheckCircle2} tone="ok" />
        <StatCard label="Escaladés" value={stats.escalated} icon={Clock} tone="alert" />
      </div>

      <Card className="p-3 space-y-2">
        <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
          <FilterSelect label="Statut" value={status} onChange={(v) => setStatus(v as IssueStatus | "all")}
            options={[["all","Tous"], ...ISSUE_STATUSES.map((s) => [s, ISSUE_STATUS_LABEL[s]] as const)]} />
          <FilterSelect label="Type" value={type} onChange={(v) => setType(v as IssueType | "all")}
            options={[["all","Tous"], ...ISSUE_TYPES.map((s) => [s, ISSUE_TYPE_LABEL[s]] as const)]} />
          <FilterSelect label="Sévérité" value={severity} onChange={(v) => setSeverity(v as IssueSeverity | "all")}
            options={[["all","Toutes"], ...ISSUE_SEVERITIES.map((s) => [s, ISSUE_SEVERITY_LABEL[s]] as const)]} />
          <FilterSelect label="Assigné" value={role} onChange={(v) => setRole(v as IssueRole | "all")}
            options={[["all","Tous"], ...ISSUE_ROLES.map((s) => [s, ISSUE_ROLE_LABEL[s]] as const)]} />
          <FilterSelect label="District" value={district} onChange={setDistrict}
            options={[["all","Tous"], ...DISTRICTS.map((d) => [d.name, d.name] as const)]} />
        </div>
      </Card>

      <div className="space-y-2">
        {issuesQ.isLoading ? (
          <Card className="p-6 text-center text-sm text-muted-foreground">Chargement…</Card>
        ) : issues.length === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">
            Aucun incident pour ce filtre.
          </Card>
        ) : issues.map((i) => (
          <Card key={i.id} className="p-3 hover:shadow-soft transition-all cursor-pointer"
                onClick={() => setSelectedId(i.id)}>
            <div className="flex items-start gap-3">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap mb-1">
                  <StatusChip status={i.status} />
                  <SeverityChip severity={i.severity} />
                  <span className="text-[11px] px-2 py-0.5 rounded-full border bg-muted text-muted-foreground border-border/60">
                    {ISSUE_TYPE_LABEL[i.issue_type]}
                  </span>
                  {i.district && (
                    <span className="text-[11px] px-2 py-0.5 rounded-full border bg-muted/40 text-foreground/80 border-border/60">
                      {i.district}
                    </span>
                  )}
                </div>
                <p className="text-sm font-medium truncate">{i.title}</p>
                <p className="text-[11px] text-muted-foreground">
                  {ISSUE_ROLE_LABEL[i.assigned_role]} · {fmtWhen(i.created_at)}
                </p>
              </div>
            </div>
          </Card>
        ))}
      </div>

      <Sheet open={!!selected} onOpenChange={(o) => !o && setSelectedId(null)}>
        <SheetContent side="right" className="w-full sm:max-w-md overflow-y-auto">
          {selected && (
            <>
              <SheetHeader className="text-left">
                <SheetTitle className="text-base">{selected.title}</SheetTitle>
                <SheetDescription>
                  {ISSUE_TYPE_LABEL[selected.issue_type]} · {fmtWhen(selected.created_at)}
                </SheetDescription>
              </SheetHeader>

              <div className="mt-4 space-y-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <StatusChip status={selected.status} />
                  <SeverityChip severity={selected.severity} />
                  <Badge variant="outline">{ISSUE_ROLE_LABEL[selected.assigned_role]}</Badge>
                  {selected.district && <Badge variant="outline">{selected.district}</Badge>}
                </div>

                {selected.description && (
                  <p className="text-sm whitespace-pre-wrap">{selected.description}</p>
                )}

                <DetailRow label="Reporter" value={selected.reporter_user_id} mono />
                <DetailRow label="Mission" value={selected.related_mission_id} mono />
                <DetailRow label="Paiement" value={selected.related_payment_intent_id} mono />
                <DetailRow label="Commande Repas" value={selected.related_food_order_id} mono />
                <DetailRow label="Annonce Marché" value={selected.related_market_listing_id} mono />
                <DetailRow label="Boutique" value={selected.related_store_id} mono />
                <DetailRow label="Restaurant" value={selected.related_restaurant_id} mono />
                <DetailRow label="Coursier" value={selected.related_driver_id} mono />
                <DetailRow label="Client" value={selected.related_customer_id} mono />
                <DetailRow label="Résolu le" value={selected.resolved_at ? fmtWhen(selected.resolved_at) : null} />

                <details className="text-xs">
                  <summary className="cursor-pointer text-muted-foreground">Métadonnées</summary>
                  <pre className="mt-2 p-2 bg-muted rounded text-[11px] overflow-x-auto">
                    {JSON.stringify(selected.metadata ?? {}, null, 2)}
                  </pre>
                </details>

                <div className="grid grid-cols-2 gap-2 pt-2">
                  <FilterSelect label="Statut" value={selected.status}
                    onChange={(v) => onChangeStatus(selected.id, v as IssueStatus)}
                    options={ISSUE_STATUSES.map((s) => [s, ISSUE_STATUS_LABEL[s]] as const)} />
                  <FilterSelect label="Sévérité" value={selected.severity}
                    onChange={(v) => onChangeSeverity(selected.id, v as IssueSeverity)}
                    options={ISSUE_SEVERITIES.map((s) => [s, ISSUE_SEVERITY_LABEL[s]] as const)} />
                  <FilterSelect label="Assigné" value={selected.assigned_role}
                    onChange={(v) => onChangeRole(selected.id, v as IssueRole)}
                    options={ISSUE_ROLES.map((s) => [s, ISSUE_ROLE_LABEL[s]] as const)} />
                </div>

                <div className="grid grid-cols-2 gap-2 pt-1">
                  <Button size="sm" variant="outline" onClick={() => onResolve(selected.id)}
                          disabled={selected.status === "resolved"}>
                    Marquer résolu
                  </Button>
                  <Button size="sm" variant="destructive" onClick={() => onEscalate(selected.id)}
                          disabled={selected.status === "escalated"}>
                    Escalader
                  </Button>
                </div>

                {selected.related_payment_intent_id && (
                  <Button asChild variant="ghost" size="sm" className="w-full">
                    <Link to="/admin/payments">
                      <ExternalLink className="w-3.5 h-3.5 mr-1" /> Voir paiement
                    </Link>
                  </Button>
                )}

                <p className="text-[11px] text-muted-foreground text-center">
                  Les actions ici ne modifient pas l'état paiement/mission/wallet — log opérationnel uniquement.
                </p>
              </div>
            </>
          )}
        </SheetContent>
      </Sheet>
    </ModulePage>
  );
}

function StatCard({ label, value, icon: Icon, tone }: {
  label: string; value: number; icon: any; tone: "ok"|"warn"|"alert"|"muted";
}) {
  return (
    <Card className="p-3">
      <div className="flex items-center gap-2">
        <Icon className={`w-4 h-4 ${tone === "alert" ? "text-destructive" : tone === "warn" ? "text-amber-600" : tone === "ok" ? "text-emerald-600" : "text-muted-foreground"}`} />
        <span className="text-[11px] text-muted-foreground uppercase tracking-wide">{label}</span>
      </div>
      <div className="text-2xl font-semibold mt-1">{value}</div>
    </Card>
  );
}

function FilterSelect({ label, value, onChange, options }: {
  label: string; value: string; onChange: (v: string) => void;
  options: ReadonlyArray<readonly [string, string]>;
}) {
  return (
    <label className="flex flex-col gap-1 text-[11px] text-muted-foreground">
      {label}
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
        <SelectContent>
          {options.map(([v, l]) => <SelectItem key={v} value={v}>{l}</SelectItem>)}
        </SelectContent>
      </Select>
    </label>
  );
}

function DetailRow({ label, value, mono }: { label: string; value: string | null; mono?: boolean }) {
  if (!value) return null;
  return (
    <div className="flex items-center justify-between gap-3 text-xs border-b border-border/40 pb-1">
      <span className="text-muted-foreground">{label}</span>
      <span className={mono ? "font-mono text-[10px] truncate max-w-[180px]" : "truncate max-w-[180px]"}>{value}</span>
    </div>
  );
}