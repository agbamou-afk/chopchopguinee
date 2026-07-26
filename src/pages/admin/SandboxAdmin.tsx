import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { toast } from "@/hooks/use-toast";
import { AlertTriangle, RefreshCw, Archive, CheckCircle2, PlayCircle, ShieldAlert, ExternalLink } from "lucide-react";
import { Link } from "react-router-dom";

type RunRow = {
  id: string; label: string | null; status: string;
  started_at: string; last_activity_at: string;
  created_by: string | null;
  intent_count: number; refund_count: number; event_count: number;
  support_count: number; unresolved_count: number;
  modules: string[]; archived_at: string | null;
};

type Metrics = {
  total_runs: number; active_runs: number; completed_runs: number; archived_runs: number;
  intents_by_state: Record<string, number>;
  refunds_by_state: Record<string, number>;
  events_total: number; needs_review: number; finalize_fails: number;
  module_counts: Record<string, number>;
  oldest_unresolved: string | null;
};

type Flag = { key: string; enabled: boolean };

const STATUS_TONE: Record<string, string> = {
  active: "bg-emerald-500/15 text-emerald-700 border-emerald-500/30",
  completed: "bg-sky-500/15 text-sky-700 border-sky-500/30",
  archived: "bg-muted text-muted-foreground border-border",
  needs_review: "bg-amber-500/15 text-amber-700 border-amber-500/30",
};

const FIXTURES = [
  { code: "OM-SBX-SUCCESS-001",       kind: "auth",   label: "Autoriser (SUCCESS)" },
  { code: "OM-SBX-REVIEW-001",        kind: "auth",   label: "À revoir (REVIEW)" },
  { code: "OM-SBX-REJECT-001",        kind: "auth",   label: "Rejeter (REJECT)" },
  { code: "OM-SBX-EXPIRED-001",       kind: "auth",   label: "Expirer" },
  { code: "OM-SBX-DUPLICATE-001",     kind: "auth",   label: "Doublon" },
  { code: "OM-SBX-FINALIZE-FAIL-001", kind: "final",  label: "Finalisation KO" },
  { code: "OM-SBX-REFUND-001",        kind: "refund", label: "Remboursement OK" },
  { code: "OM-SBX-REFUND-REVIEW-001", kind: "refund", label: "Remboursement à revoir" },
];

export default function SandboxAdmin() {
  const { isSuperAdmin, role } = useAdminAuth();
  const canControl = isSuperAdmin;
  const canRead = role === "god_admin" || role === "finance_admin";

  const [flags, setFlags] = useState<Flag[]>([]);
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [runs, setRuns] = useState<RunRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<RunRow | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refInput, setRefInput] = useState<Record<string, string>>({});

  const active = useMemo(() => {
    const env = flags.find((f) => f.key === "om_environment")?.enabled;
    const sbx = flags.find((f) => f.key === "om_sandbox_enabled")?.enabled;
    return !!(env && sbx);
  }, [flags]);

  const load = async () => {
    setLoading(true);
    const [flagsRes, metricsRes, runsRes] = await Promise.all([
      supabase.from("feature_flags").select("key,enabled").in("key", ["om_environment","om_sandbox_enabled","om_checkout_enabled"]),
      supabase.rpc("om_sandbox_admin_metrics"),
      supabase.rpc("om_sandbox_admin_list_runs", { p_limit: 200 }),
    ]);
    setFlags((flagsRes.data ?? []) as Flag[]);
    setMetrics((metricsRes.data ?? null) as Metrics | null);
    setRuns((runsRes.data ?? []) as RunRow[]);
    setLoading(false);
  };

  useEffect(() => { if (canRead) void load(); }, [canRead]);

  const openDetail = async (run: RunRow) => {
    setSelected(run);
    setDetail(null);
    const { data, error } = await supabase.rpc("om_sandbox_admin_run_detail", { p_test_run_id: run.id });
    if (error) { toast({ title: "Erreur", description: error.message, variant: "destructive" }); return; }
    setDetail(data);
  };

  const rpc = async (fn: string, args: any, successMsg: string) => {
    if (!canControl) return;
    setBusy(fn);
    const { data, error } = await supabase.rpc(fn as any, args);
    setBusy(null);
    if (error) {
      toast({ title: "Échec", description: error.message, variant: "destructive" });
      return null;
    }
    toast({ title: successMsg, description: JSON.stringify(data).slice(0, 220) });
    void load();
    if (selected) void openDetail(selected);
    return data;
  };

  if (!canRead) {
    return (
      <ModulePage module="payments" title="Orange Money Sandbox">
        <Card className="p-6 text-sm">Accès refusé.</Card>
      </ModulePage>
    );
  }

  return (
    <ModulePage
      module="payments"
      title="Orange Money Sandbox"
      subtitle="Environnement de test — aucune valeur financière réelle."
      actions={
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-1.5 ${loading ? "animate-spin" : ""}`} /> Rafraîchir
        </Button>
      }
    >
      {/* Status banner */}
      <Card className={`p-3 mb-4 border ${active ? "border-emerald-500/30 bg-emerald-500/5" : "border-amber-500/40 bg-amber-500/5"}`}>
        <div className="flex items-start gap-3">
          <ShieldAlert className={`h-4 w-4 mt-0.5 ${active ? "text-emerald-600" : "text-amber-600"}`} />
          <div className="text-xs">
            {active ? (
              <p className="font-medium text-emerald-800 dark:text-emerald-200">
                Sandbox actif — utilisez les références déterministes OM-SBX-*.
              </p>
            ) : (
              <p className="font-medium text-amber-800 dark:text-amber-200">
                Sandbox désactivé — activez les deux indicateurs de test pour exécuter une simulation.
              </p>
            )}
            <p className="mt-0.5 text-muted-foreground">
              Indicateurs&nbsp;: <code>om_environment</code>={String(!!flags.find((f) => f.key === "om_environment")?.enabled)},{" "}
              <code>om_sandbox_enabled</code>={String(!!flags.find((f) => f.key === "om_sandbox_enabled")?.enabled)} — gérez dans{" "}
              <Link to="/admin/flags" className="text-primary underline">Feature flags</Link>. Retour aux{" "}
              <Link to="/admin/payments" className="text-primary underline">paiements en production</Link>.
            </p>
          </div>
        </div>
      </Card>

      {/* Metric cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-4">
        <Metric label="Runs actifs" value={metrics?.active_runs ?? 0} sub={`Total ${metrics?.total_runs ?? 0}`} />
        <Metric label="Runs archivés" value={metrics?.archived_runs ?? 0} sub={`Complétés ${metrics?.completed_runs ?? 0}`} />
        <Metric label="À revoir" value={metrics?.needs_review ?? 0} sub={`Finalize KO ${metrics?.finalize_fails ?? 0}`} />
        <Metric label="Provider events" value={metrics?.events_total ?? 0} sub={`Modules ${Object.keys(metrics?.module_counts ?? {}).length}`} />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-2 mb-4">
        <Card className="p-3">
          <p className="text-[11px] uppercase tracking-wider text-muted-foreground mb-1">Intents (sandbox)</p>
          <BarList items={metrics?.intents_by_state ?? {}} />
        </Card>
        <Card className="p-3">
          <p className="text-[11px] uppercase tracking-wider text-muted-foreground mb-1">Refunds (sandbox)</p>
          <BarList items={metrics?.refunds_by_state ?? {}} />
        </Card>
      </div>

      {/* Test runs */}
      <Card className="p-0">
        <div className="px-3 py-2 border-b text-[11px] uppercase tracking-wider text-muted-foreground">
          Test runs ({runs.length})
        </div>
        <div className="divide-y">
          {runs.length === 0 && !loading && (
            <p className="p-4 text-sm text-muted-foreground">Aucun test run enregistré.</p>
          )}
          {runs.map((r) => (
            <button
              key={r.id}
              onClick={() => openDetail(r)}
              className="w-full text-left p-3 hover:bg-muted/40 flex items-start justify-between gap-3"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-mono text-[11px] truncate">{r.id.slice(0, 8)}…</span>
                  <Badge variant="outline" className={STATUS_TONE[r.status] ?? ""}>{r.status}</Badge>
                  {r.modules.map((m) => <Badge key={m} variant="secondary" className="text-[10px]">{m}</Badge>)}
                </div>
                <p className="text-[11px] text-muted-foreground mt-1">
                  Démarré {new Date(r.started_at).toLocaleString("fr-FR")} · Activité {new Date(r.last_activity_at).toLocaleString("fr-FR")}
                </p>
              </div>
              <div className="text-right text-[11px] text-muted-foreground shrink-0">
                <div>{r.intent_count} intents · {r.refund_count} refunds</div>
                <div>{r.event_count} events · {r.unresolved_count} en cours</div>
                {r.support_count > 0 && <div className="text-amber-600">{r.support_count} support</div>}
              </div>
            </button>
          ))}
        </div>
      </Card>

      {/* Detail sheet */}
      <Sheet open={!!selected} onOpenChange={(o) => !o && (setSelected(null), setDetail(null))}>
        <SheetContent side="right" className="w-full sm:max-w-2xl overflow-y-auto">
          <SheetHeader>
            <SheetTitle>Test run {selected?.id.slice(0, 8)}…</SheetTitle>
          </SheetHeader>
          {!detail ? (
            <p className="text-sm text-muted-foreground p-4">Chargement…</p>
          ) : (
            <RunDetail
              detail={detail}
              canControl={canControl && active}
              active={active}
              busy={busy}
              refInput={refInput}
              setRefInput={setRefInput}
              onRpc={rpc}
              runId={selected!.id}
              archived={selected?.status === "archived"}
            />
          )}
        </SheetContent>
      </Sheet>
    </ModulePage>
  );
}

function Metric({ label, value, sub }: { label: string; value: number; sub?: string }) {
  return (
    <Card className="p-3">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="text-2xl font-bold tabular-nums">{value}</p>
      {sub && <p className="text-[10px] text-muted-foreground">{sub}</p>}
    </Card>
  );
}

function BarList({ items }: { items: Record<string, number> }) {
  const entries = Object.entries(items);
  if (!entries.length) return <p className="text-xs text-muted-foreground">—</p>;
  const max = Math.max(...entries.map(([, v]) => v));
  return (
    <ul className="space-y-1">
      {entries.map(([k, v]) => (
        <li key={k} className="flex items-center gap-2 text-xs">
          <span className="w-28 truncate font-mono">{k}</span>
          <div className="flex-1 h-2 bg-muted rounded overflow-hidden">
            <div className="h-full bg-primary/50" style={{ width: `${(v / max) * 100}%` }} />
          </div>
          <span className="tabular-nums w-8 text-right">{v}</span>
        </li>
      ))}
    </ul>
  );
}

function RunDetail(props: {
  detail: any; canControl: boolean; active: boolean; archived: boolean;
  busy: string | null; refInput: Record<string, string>;
  setRefInput: (r: Record<string, string>) => void;
  onRpc: (fn: string, args: any, msg: string) => Promise<any>;
  runId: string;
}) {
  const { detail, canControl, active, archived, busy, refInput, setRefInput, onRpc, runId } = props;
  const intents: any[] = detail.intents ?? [];
  const refunds: any[] = detail.refunds ?? [];

  return (
    <div className="space-y-4 py-3 text-sm">
      {archived && (
        <div className="p-2 rounded bg-muted text-[11px] text-muted-foreground">
          Ce run est archivé — aucune simulation n'est possible.
        </div>
      )}

      {/* Run actions */}
      {canControl && !archived && (
        <div className="flex gap-2 flex-wrap">
          <Button size="sm" variant="outline"
            onClick={() => onRpc("om_sandbox_complete_test_run", { p_test_run_id: runId, p_notes: null }, "Run complété")}
            disabled={busy !== null}>
            <CheckCircle2 className="h-3.5 w-3.5 mr-1" /> Compléter
          </Button>
          <Button size="sm" variant="destructive"
            onClick={() => {
              if (!confirm("Archiver ce run ? Les données sont préservées mais plus aucune simulation ne sera possible.")) return;
              onRpc("om_sandbox_archive_test_run", { p_test_run_id: runId, p_notes: null }, "Run archivé");
            }}
            disabled={busy !== null}>
            <Archive className="h-3.5 w-3.5 mr-1" /> Archiver
          </Button>
        </div>
      )}

      {/* Intents */}
      <section>
        <h4 className="text-[11px] uppercase tracking-wider text-muted-foreground mb-2">Intents ({intents.length})</h4>
        <ul className="space-y-2">
          {intents.map((i: any) => (
            <li key={i.id} className="border rounded p-2">
              <div className="flex items-center justify-between">
                <div className="min-w-0">
                  <p className="font-mono text-[11px] truncate">{i.id}</p>
                  <p className="text-[11px] text-muted-foreground">
                    {i.source_module ?? "—"} · {i.amount_gnf} GNF · <Badge variant="outline">{i.state}</Badge>
                  </p>
                </div>
              </div>
              {canControl && active && !archived && i.state === "pending" && (
                <div className="mt-2 flex gap-1 flex-wrap">
                  {FIXTURES.filter((f) => f.kind === "auth").map((f) => (
                    <Button key={f.code} size="sm" variant="outline" className="h-7 text-[11px]"
                      onClick={() => onRpc("om_payment_submit_sandbox_reference",
                        { p_payment_intent_id: i.id, p_provider_reference: f.code, p_provider: "orange_money", p_test_run_id: runId },
                        `Simulé ${f.code}`)}
                      disabled={busy !== null}>
                      <PlayCircle className="h-3 w-3 mr-1" /> {f.label}
                    </Button>
                  ))}
                </div>
              )}
              {canControl && active && !archived && i.state === "authorized" && (
                <div className="mt-2">
                  <Button size="sm" variant="outline" className="h-7 text-[11px]"
                    onClick={() => onRpc("om_sandbox_finalize_authorized_intent", { p_payment_intent_id: i.id }, "Finalisé")}
                    disabled={busy !== null}>
                    Finaliser (créer la ressource)
                  </Button>
                </div>
              )}
            </li>
          ))}
          {intents.length === 0 && <p className="text-xs text-muted-foreground">Aucun intent.</p>}
        </ul>
      </section>

      {/* Refunds */}
      <section>
        <h4 className="text-[11px] uppercase tracking-wider text-muted-foreground mb-2">Refunds ({refunds.length})</h4>
        <ul className="space-y-2">
          {refunds.map((r: any) => (
            <li key={r.id} className="border rounded p-2">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-mono text-[11px] truncate">{r.id}</p>
                  <p className="text-[11px] text-muted-foreground">
                    {r.source_module} · remb {r.amount_gnf} GNF · frais {r.fee_gnf} · <Badge variant="outline">{r.status}</Badge>
                  </p>
                </div>
              </div>
              {canControl && active && !archived && (r.status === "pending" || r.status === "in_review") && (
                <div className="mt-2 flex gap-1 flex-wrap">
                  {FIXTURES.filter((f) => f.kind === "refund").map((f) => (
                    <Button key={f.code} size="sm" variant="outline" className="h-7 text-[11px]"
                      onClick={() => onRpc("om_sandbox_submit_refund_reference",
                        { p_refund_request_id: r.id, p_provider_reference: f.code, p_test_run_id: runId },
                        `Refund ${f.code}`)}
                      disabled={busy !== null}>
                      {f.label}
                    </Button>
                  ))}
                </div>
              )}
            </li>
          ))}
          {refunds.length === 0 && <p className="text-xs text-muted-foreground">Aucun refund.</p>}
        </ul>
      </section>

      {/* Correlated logs */}
      <section className="grid grid-cols-1 gap-2">
        <LogList title="Provider events" items={detail.provider_events} render={(e: any) => `${e.kind ?? "?"} · ${e.provider_transaction_id ?? "—"} · ${e.amount_gnf ?? 0} GNF`} />
        <LogList title="Reconciliation" items={detail.reconciliation} render={(e: any) => `${e.event_type ?? e.kind ?? "?"} · intent ${String(e.payment_intent_id ?? "").slice(0,8)}…`} />
        <LogList title="Support issues" items={detail.support_issues} render={(s: any) => `${s.severity} · ${s.category} · ${s.summary ?? ""}`} />
      </section>

      <p className="text-[10px] text-muted-foreground">
        Les paiements sandbox ne touchent jamais le master wallet, les soldes chauffeurs ou les payables marchands.
      </p>
    </div>
  );
}

function LogList({ title, items, render }: { title: string; items: any[]; render: (x: any) => string }) {
  if (!items?.length) return null;
  return (
    <div>
      <p className="text-[11px] uppercase tracking-wider text-muted-foreground mb-1">{title} ({items.length})</p>
      <ul className="space-y-1">
        {items.slice(0, 20).map((it, i) => (
          <li key={i} className="text-[11px] font-mono text-muted-foreground">
            {new Date(it.created_at).toLocaleString("fr-FR")} — {render(it)}
          </li>
        ))}
      </ul>
    </div>
  );
}