import { useCallback, useEffect, useMemo, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/format";
import {
  fetchMarcheOpsQueue,
  fetchMarcheOpsCase,
  runMarcheOpsCommand,
  OPS_ACTION_LABEL,
  OPS_CASE_TYPE_LABEL,
  OPS_STATUS_LABEL,
  OPS_STATUS_ORDER,
  type MarcheOpsAction,
  type MarcheOpsCaseDetail,
  type MarcheOpsQueue,
  type MarcheOpsStatus,
} from "@/lib/marche/ops";

const SEVERITY_TONE: Record<string, string> = {
  critical: "bg-destructive/15 text-destructive",
  high: "bg-amber-500/15 text-amber-600",
  normal: "bg-muted text-muted-foreground",
  low: "bg-muted text-muted-foreground",
};

/** Actions requiring an explicit reason before the server will accept them. */
const REASON_ACTIONS = new Set<MarcheOpsAction>([
  "suspend_merchant", "restore_merchant", "quarantine_listing", "restore_listing",
  "restrict_user", "unrestrict_user", "moderate_rating", "restore_rating",
  "resolve", "dismiss", "reopen", "escalate", "record_finance_resolution",
]);

export default function MarcheOpsAdmin() {
  const [queue, setQueue] = useState<MarcheOpsQueue | null>(null);
  const [status, setStatus] = useState<MarcheOpsStatus | null>("open");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<MarcheOpsCaseDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<MarcheOpsAction | null>(null);

  const loadQueue = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setQueue(await fetchMarcheOpsQueue({ status, search: search.trim() || null }));
    } catch (e) {
      setQueue(null);
      setError(e instanceof Error ? e.message : "Erreur inconnue");
    } finally {
      setLoading(false);
    }
  }, [status, search]);

  const loadDetail = useCallback(async (caseId: string) => {
    setDetailLoading(true);
    try {
      setDetail(await fetchMarcheOpsCase(caseId));
    } catch (e) {
      setDetail(null);
      toast({ title: "Dossier indisponible", description: e instanceof Error ? e.message : "", variant: "destructive" });
    } finally {
      setDetailLoading(false);
    }
  }, []);

  useEffect(() => { void loadQueue(); }, [loadQueue]);
  useEffect(() => { if (selected) void loadDetail(selected); }, [selected, loadDetail]);

  const counts = queue?.counts ?? {};

  const runAction = async (action: MarcheOpsAction) => {
    if (!detail) return;
    if (REASON_ACTIONS.has(action) && !reason.trim()) {
      toast({ title: "Motif obligatoire", description: "Renseignez un motif avant cette action.", variant: "destructive" });
      return;
    }
    setBusy(action);
    try {
      await runMarcheOpsCommand({
        caseId: detail.case_id,
        action,
        requestId: crypto.randomUUID(),
        reasonCode: reason.trim() || null,
        note: note.trim() || null,
      });
      toast({ title: OPS_ACTION_LABEL[action], description: "Intervention enregistrée." });
      setReason("");
      setNote("");
      await Promise.all([loadDetail(detail.case_id), loadQueue()]);
    } catch (e) {
      toast({ title: "Action refusée", description: e instanceof Error ? e.message : "", variant: "destructive" });
    } finally {
      setBusy(null);
    }
  };

  const subjectLines = useMemo(() => {
    if (!detail) return [];
    const s = detail.subjects;
    const out: { label: string; value: string }[] = [];
    if (s.store) out.push({ label: "Boutique", value: `${s.store.name ?? s.store.id} — ${s.store.ops_suspended ? "suspendue (ops)" : s.store.status ?? "—"}` });
    if (s.listing) out.push({ label: "Annonce", value: `${s.listing.title ?? s.listing.id} — ${s.listing.ops_quarantined ? "en quarantaine" : s.listing.is_orderable ? "commandable" : s.listing.refusal_reason ?? "non commandable"}` });
    if (s.order) out.push({ label: "Commande", value: `${s.order.fulfillment_state} · ${formatGNF(s.order.merchandise_subtotal_gnf ?? 0)}${s.order.merchant_payable_gnf != null ? ` · dû marchand ${formatGNF(s.order.merchant_payable_gnf)}` : ""}` });
    if (s.mission) out.push({ label: "Mission", value: `${s.mission.state}${s.mission.verified_spend_gnf != null ? ` · dépense vérifiée ${formatGNF(s.mission.verified_spend_gnf)}` : ""}` });
    if (s.reputation_event) out.push({ label: "Évaluation", value: `${s.reputation_event.subject_kind} · note ${s.reputation_event.overall_score ?? "—"}${s.reputation_event.moderated ? " · modérée" : ""}` });
    if (s.customer_user_id) out.push({ label: "Client", value: s.customer_user_id });
    if (s.shopper_user_id) out.push({ label: "Acheteur-livreur", value: s.shopper_user_id });
    return out;
  }, [detail]);

  return (
    <ModulePage
      module="marche"
      title="Opérations Marché"
      subtitle="Dossiers d'exception, contrôles prospectifs et historique d'intervention. Les interventions ne réécrivent jamais l'historique."
      actions={<Button size="sm" variant="outline" onClick={() => void loadQueue()}>Rafraîchir</Button>}
    >
      <div className="flex flex-wrap items-center gap-2">
        {OPS_STATUS_ORDER.map((s) => (
          <Button
            key={s}
            size="sm"
            variant={status === s ? "default" : "outline"}
            onClick={() => { setStatus(s); setSelected(null); setDetail(null); }}
          >
            {OPS_STATUS_LABEL[s]} <span className="ml-1.5 opacity-70">{counts[s] ?? 0}</span>
          </Button>
        ))}
        <Button size="sm" variant={status === null ? "default" : "outline"} onClick={() => { setStatus(null); setSelected(null); setDetail(null); }}>
          Tous
        </Button>
        <Input
          className="h-8 w-56"
          placeholder="Boutique, motif, note…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") void loadQueue(); }}
        />
      </div>

      {error && (
        <Card className="p-4 border-dashed">
          <p className="text-sm text-muted-foreground">{error}</p>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-[1fr_1.15fr]">
        <Card className="p-0 overflow-hidden">
          {loading ? (
            <div className="p-4 space-y-2">
              {[0, 1, 2].map((i) => <Skeleton key={i} className="h-12 w-full" />)}
            </div>
          ) : !queue || queue.items.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              Aucun dossier pour ce filtre.
            </div>
          ) : (
            <ul className="divide-y divide-border/60">
              {queue.items.map((it) => (
                <li key={it.case_id}>
                  <button
                    type="button"
                    onClick={() => setSelected(it.case_id)}
                    className={`w-full text-left px-4 py-3 hover:bg-muted/50 transition ${selected === it.case_id ? "bg-muted/60" : ""}`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[13px] font-medium truncate">
                        {OPS_CASE_TYPE_LABEL[it.case_type] ?? it.case_type}
                      </span>
                      <Badge variant="secondary" className={SEVERITY_TONE[it.severity] ?? ""}>{it.severity}</Badge>
                    </div>
                    <p className="text-[12px] text-muted-foreground truncate mt-0.5">
                      {it.store_name ?? "—"} · {it.reason_code} · {it.age_hours}h
                    </p>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card className="p-4">
          {!selected ? (
            <p className="text-sm text-muted-foreground">Sélectionnez un dossier pour voir son détail et les actions autorisées.</p>
          ) : detailLoading || !detail ? (
            <div className="space-y-2">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-10 w-full" />)}</div>
          ) : (
            <div className="space-y-4">
              <div>
                <p className="admin-eyebrow">{detail.status} · {detail.source}</p>
                <h2 className="text-[15px] font-semibold">{OPS_CASE_TYPE_LABEL[detail.case_type] ?? detail.case_type}</h2>
                <p className="text-[12px] text-muted-foreground">{detail.reason_code}{detail.note ? ` — ${detail.note}` : ""}</p>
              </div>

              {subjectLines.length > 0 && (
                <div className="rounded-md border border-border/60 divide-y divide-border/60">
                  {subjectLines.map((l) => (
                    <div key={l.label} className="flex gap-3 px-3 py-2 text-[12px]">
                      <span className="w-32 shrink-0 text-muted-foreground">{l.label}</span>
                      <span className="truncate">{l.value}</span>
                    </div>
                  ))}
                </div>
              )}

              {detail.controls.length > 0 && (
                <div>
                  <p className="admin-eyebrow mb-1">Contrôles</p>
                  <div className="flex flex-wrap gap-1.5">
                    {detail.controls.map((c) => (
                      <Badge key={c.id} variant={c.active ? "destructive" : "secondary"}>
                        {c.control_kind}{c.active ? "" : " (levé)"}
                      </Badge>
                    ))}
                  </div>
                </div>
              )}

              <div className="space-y-2">
                <Input placeholder="Motif (obligatoire pour les sanctions)" value={reason} onChange={(e) => setReason(e.target.value)} />
                <Textarea placeholder="Note interne (optionnelle)" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
                <div className="flex flex-wrap gap-2">
                  {detail.allowed_actions.length === 0 ? (
                    <p className="text-[12px] text-muted-foreground">Votre rôle ({detail.actor_role}) n'a aucune action disponible sur ce dossier.</p>
                  ) : detail.allowed_actions.map((a) => (
                    <Button key={a} size="sm" variant={a === "resolve" ? "default" : "outline"} disabled={busy !== null} onClick={() => void runAction(a)}>
                      {busy === a ? "…" : OPS_ACTION_LABEL[a] ?? a}
                    </Button>
                  ))}
                </div>
              </div>

              <div>
                <p className="admin-eyebrow mb-1">Historique (immuable)</p>
                {detail.timeline.length === 0 ? (
                  <p className="text-[12px] text-muted-foreground">Aucune intervention enregistrée.</p>
                ) : (
                  <ol className="space-y-1.5">
                    {detail.timeline.map((ev) => (
                      <li key={ev.id} className="text-[12px] border-l-2 border-border pl-2">
                        <span className="font-medium">{OPS_ACTION_LABEL[ev.action as MarcheOpsAction] ?? ev.action}</span>
                        <span className="text-muted-foreground"> · {ev.actor_role} · {new Date(ev.created_at).toLocaleString("fr-FR")}</span>
                        {ev.reason_code && <span className="text-muted-foreground"> · {ev.reason_code}</span>}
                        {ev.note && <p className="text-muted-foreground">{ev.note}</p>}
                      </li>
                    ))}
                  </ol>
                )}
              </div>
            </div>
          )}
        </Card>
      </div>
    </ModulePage>
  );
}
