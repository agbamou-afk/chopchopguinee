import { useEffect, useMemo, useState } from "react";
import { Loader2, Download, AlertTriangle, Search } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { ScrollArea } from "@/components/ui/scroll-area";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { toast } from "@/hooks/use-toast";
import {
  listIntents,
  listReconciliationEvents,
  confirmIntent,
  failIntent,
  simulateProviderForIntent,
  maskMsisdn,
  stateLabel,
  stateTone,
  providerLabel,
  reviewSignals,
  needsReview,
  reviewSignalLabel,
  reconEventLabel,
  reconEventTone,
  toCsv,
  type PaymentIntent,
  type PaymentReconciliationEvent,
  type PaymentState,
  type SimulatedKind,
} from "@/lib/payments";
import { formatGNF } from "@/lib/format";

type TabKey = "all" | "pending" | "confirmed" | "failed" | "expired" | "review" | "events";

const TONE_CLASS: Record<ReturnType<typeof stateTone>, string> = {
  pending:    "bg-amber-500/10 text-amber-600 border-amber-500/20",
  processing: "bg-sky-500/10 text-sky-600 border-sky-500/20",
  ok:         "bg-emerald-600/10 text-emerald-700 border-emerald-600/20",
  failed:     "bg-red-500/10 text-red-600 border-red-500/20",
  cancelled:  "bg-muted text-muted-foreground border-border",
  muted:      "bg-muted text-muted-foreground border-border",
};

function StateChip({ state }: { state: PaymentState }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium ${TONE_CLASS[stateTone(state)]}`}>
      {stateLabel(state)}
    </span>
  );
}

function RecentEventDot({ tone }: { tone: ReturnType<typeof reconEventTone> }) {
  const c = tone === "ok" ? "bg-emerald-500"
    : tone === "failed" ? "bg-red-500"
    : tone === "pending" ? "bg-amber-500"
    : "bg-muted-foreground/40";
  return <span className={`inline-block h-2 w-2 rounded-full ${c}`} />;
}

export default function PaymentsAdmin() {
  const { isSuperAdmin, can } = useAdminAuth();
  const canSimulate = isSuperAdmin;
  const canExport = can("payments", "export") || isSuperAdmin;

  const [items, setItems] = useState<PaymentIntent[]>([]);
  const [eventsByIntent, setEventsByIntent] = useState<Record<string, PaymentReconciliationEvent[]>>({});
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<TabKey>("all");
  const [query, setQuery] = useState("");
  const [providerFilter, setProviderFilter] = useState<string>("all");
  const [purposeFilter, setPurposeFilter] = useState<string>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const list = await listIntents({ limit: 200 });
      setItems(list);
      // Prefetch reconciliation events for review classification (lightweight; capped intents).
      const pairs = await Promise.all(
        list.map(async (i) => [i.id, await listReconciliationEvents(i.id).catch(() => [])] as const),
      );
      const map: Record<string, PaymentReconciliationEvent[]> = {};
      for (const [id, evs] of pairs) map[id] = evs;
      setEventsByIntent(map);
    } catch (e) {
      toast({ title: "Erreur", description: (e as Error).message });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const selected = useMemo(
    () => items.find((i) => i.id === selectedId) ?? null,
    [items, selectedId],
  );

  const counters = useMemo(() => {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const isToday = (iso: string) => new Date(iso).getTime() >= today.getTime();
    return {
      pending: items.filter((i) => i.state === "pending" || i.state === "processing").length,
      confirmedToday: items.filter((i) => i.state === "confirmed" && isToday(i.updated_at)).length,
      failed: items.filter((i) => i.state === "failed" || i.state === "expired").length,
      review: items.filter((i) => needsReview(i, eventsByIntent[i.id])).length,
    };
  }, [items, eventsByIntent]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((i) => {
      if (providerFilter !== "all" && i.provider !== providerFilter) return false;
      if (purposeFilter !== "all" && i.purpose !== purposeFilter) return false;
      if (tab === "pending" && !(i.state === "pending" || i.state === "processing")) return false;
      if (tab === "confirmed" && i.state !== "confirmed") return false;
      if (tab === "failed" && !(i.state === "failed" || i.state === "cancelled")) return false;
      if (tab === "expired" && i.state !== "expired") return false;
      if (tab === "review" && !needsReview(i, eventsByIntent[i.id])) return false;
      if (!q) return true;
      const phone = ((i.metadata as { phone_number?: string } | null)?.phone_number ?? "").toLowerCase();
      return (
        i.internal_reference.toLowerCase().includes(q) ||
        (i.provider_reference ?? "").toLowerCase().includes(q) ||
        i.user_id.toLowerCase().includes(q) ||
        phone.includes(q) ||
        String(i.amount_gnf).includes(q)
      );
    });
  }, [items, query, providerFilter, purposeFilter, tab, eventsByIntent]);

  const allEvents = useMemo(() => {
    const flat: Array<PaymentReconciliationEvent & { intentRef: string }> = [];
    for (const i of items) {
      const evs = eventsByIntent[i.id] ?? [];
      for (const e of evs) flat.push({ ...e, intentRef: i.internal_reference });
    }
    return flat.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  }, [items, eventsByIntent]);

  const onConfirm = async (id: string) => {
    try { await confirmIntent(id, undefined, "admin test confirmation"); await load(); }
    catch (e) { toast({ title: "Erreur", description: (e as Error).message }); }
  };
  const onFail = async (id: string) => {
    try { await failIntent(id, "admin marked failed"); await load(); }
    catch (e) { toast({ title: "Erreur", description: (e as Error).message }); }
  };
  const onSimulate = async (id: string, kind: SimulatedKind) => {
    try {
      const r = await simulateProviderForIntent(id, kind);
      toast({
        title: `Simulation · ${kind}`,
        description: r.applied === "ignored" ? `Ignoré (${r.reason})` : `Appliqué: ${r.applied}`,
      });
      await load();
    } catch (e) {
      toast({ title: "Erreur", description: (e as Error).message });
    }
  };

  const onExport = () => {
    const csv = toCsv(filtered);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `wongo-payments-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const actions = (
    <div className="flex items-center gap-2">
      {canExport && (
        <Button size="sm" variant="outline" onClick={onExport} disabled={filtered.length === 0}>
          <Download className="w-3.5 h-3.5 mr-1" /> CSV
        </Button>
      )}
    </div>
  );

  return (
    <ModulePage module="payments" title="Paiements (réconciliation)" subtitle="Centre opérationnel WONGO Wallet" actions={actions}>
      {/* Summary counters */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
        <SummaryCard label="En attente" value={counters.pending} tone="pending" />
        <SummaryCard label="Confirmés aujourd'hui" value={counters.confirmedToday} tone="ok" />
        <SummaryCard label="Échoués / expirés" value={counters.failed} tone="failed" />
        <SummaryCard label="À vérifier" value={counters.review} tone="warn" />
      </div>

      {/* Filters */}
      <Card className="p-3 space-y-2">
        <div className="flex flex-col sm:flex-row gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground" />
            <Input
              placeholder="Réf. WONGO, réf. provider, user, téléphone, montant…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="pl-8 h-9"
            />
          </div>
          <Select value={providerFilter} onValueChange={setProviderFilter}>
            <SelectTrigger className="h-9 sm:w-[160px]"><SelectValue placeholder="Provider" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tous providers</SelectItem>
              <SelectItem value="orange_money">Orange Money</SelectItem>
              <SelectItem value="mtn_money">MTN Money</SelectItem>
              <SelectItem value="cash">Espèces</SelectItem>
              <SelectItem value="manual">Manuel</SelectItem>
              <SelectItem value="internal">Interne</SelectItem>
              <SelectItem value="agent">Agent</SelectItem>
            </SelectContent>
          </Select>
          <Select value={purposeFilter} onValueChange={setPurposeFilter}>
            <SelectTrigger className="h-9 sm:w-[160px]"><SelectValue placeholder="Objet" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tous objets</SelectItem>
              <SelectItem value="wallet_topup">Top-up wallet</SelectItem>
              <SelectItem value="repas_payment">Repas</SelectItem>
              <SelectItem value="marche_payment">Marché</SelectItem>
              <SelectItem value="courier_payout">Payout coursier</SelectItem>
              <SelectItem value="merchant_settlement">Settlement marchand</SelectItem>
              <SelectItem value="refund">Remboursement</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </Card>

      {/* Tabs */}
      <Tabs value={tab} onValueChange={(v) => setTab(v as TabKey)}>
        <TabsList className="w-full justify-start overflow-x-auto">
          <TabsTrigger value="all">Tous</TabsTrigger>
          <TabsTrigger value="pending">En attente</TabsTrigger>
          <TabsTrigger value="confirmed">Confirmés</TabsTrigger>
          <TabsTrigger value="failed">Échoués</TabsTrigger>
          <TabsTrigger value="expired">Expirés</TabsTrigger>
          <TabsTrigger value="review">À vérifier</TabsTrigger>
          <TabsTrigger value="events">Événements</TabsTrigger>
        </TabsList>
      </Tabs>

      {loading ? (
        <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="w-4 h-4 animate-spin" /> Chargement…</div>
      ) : tab === "events" ? (
        <EventsList events={allEvents} />
      ) : filtered.length === 0 ? (
        <Card className="p-6 text-center border-dashed">
          <p className="text-sm text-muted-foreground">Aucun intent pour ce filtre.</p>
        </Card>
      ) : (
        <div className="space-y-2">
          {filtered.map((it) => (
            <IntentRow
              key={it.id}
              intent={it}
              events={eventsByIntent[it.id] ?? []}
              onOpen={() => setSelectedId(it.id)}
            />
          ))}
        </div>
      )}

      <Sheet open={!!selected} onOpenChange={(o) => !o && setSelectedId(null)}>
        <SheetContent side="right" className="w-full sm:max-w-lg overflow-y-auto">
          {selected && (
            <DetailContent
              intent={selected}
              events={eventsByIntent[selected.id] ?? []}
              canSimulate={canSimulate}
              onConfirm={() => onConfirm(selected.id)}
              onFail={() => onFail(selected.id)}
              onSimulate={(k) => onSimulate(selected.id, k)}
            />
          )}
        </SheetContent>
      </Sheet>

      {!canSimulate && (
        <p className="text-[11px] text-muted-foreground mt-2">
          Lecture / réconciliation autorisées. Les contrôles de simulation sont réservés au Super Admin.
        </p>
      )}
    </ModulePage>
  );
}

function SummaryCard({ label, value, tone }: { label: string; value: number; tone: "pending" | "ok" | "failed" | "warn" }) {
  const t =
    tone === "ok" ? "text-emerald-700"
    : tone === "failed" ? "text-red-600"
    : tone === "warn" ? "text-amber-600"
    : "text-sky-600";
  return (
    <Card className="p-3">
      <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`text-2xl font-semibold mt-0.5 ${t}`}>{value}</p>
    </Card>
  );
}

function IntentRow({
  intent, events, onOpen,
}: { intent: PaymentIntent; events: PaymentReconciliationEvent[]; onOpen: () => void }) {
  const phone = (intent.metadata as { phone_number?: string } | null)?.phone_number;
  const flagged = needsReview(intent, events);
  return (
    <Card
      className="p-3 flex items-center justify-between gap-3 cursor-pointer hover:bg-accent/30 transition-colors"
      onClick={onOpen}
    >
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2 flex-wrap">
          <p className="font-mono text-[12px] font-semibold truncate">{intent.internal_reference}</p>
          <StateChip state={intent.state} />
          {flagged && (
            <Badge variant="outline" className="text-[10px] border-amber-500/40 text-amber-600 gap-1">
              <AlertTriangle className="w-3 h-3" /> À vérifier
            </Badge>
          )}
        </div>
        <p className="text-xs text-muted-foreground mt-0.5 truncate">
          {providerLabel(intent.provider)} · {intent.purpose} · {formatGNF(intent.amount_gnf)}
        </p>
        <p className="text-[11px] text-muted-foreground mt-0.5">
          {new Date(intent.created_at).toLocaleString("fr-FR")}
          {phone && <> · <span className="font-mono">{maskMsisdn(phone)}</span></>}
        </p>
      </div>
    </Card>
  );
}

function EventsList({ events }: { events: Array<PaymentReconciliationEvent & { intentRef: string }> }) {
  if (events.length === 0) {
    return <Card className="p-6 text-center border-dashed"><p className="text-sm text-muted-foreground">Aucun événement.</p></Card>;
  }
  return (
    <div className="space-y-1.5">
      {events.map((e) => (
        <Card key={e.id} className="p-2.5 flex items-center gap-3">
          <RecentEventDot tone={reconEventTone(e.event_type)} />
          <div className="min-w-0 flex-1">
            <p className="text-xs">
              <span className="font-medium">{reconEventLabel(e.event_type)}</span>
              {e.provider && <span className="text-muted-foreground"> · {providerLabel(e.provider)}</span>}
            </p>
            <p className="text-[11px] text-muted-foreground font-mono truncate">{e.intentRef}</p>
          </div>
          <p className="text-[11px] text-muted-foreground shrink-0">{new Date(e.created_at).toLocaleString("fr-FR")}</p>
        </Card>
      ))}
    </div>
  );
}

function DetailContent({
  intent, events, canSimulate, onConfirm, onFail, onSimulate,
}: {
  intent: PaymentIntent;
  events: PaymentReconciliationEvent[];
  canSimulate: boolean;
  onConfirm: () => void;
  onFail: () => void;
  onSimulate: (k: SimulatedKind) => void;
}) {
  const phone = (intent.metadata as { phone_number?: string } | null)?.phone_number;
  const signals = reviewSignals(intent, events);
  const terminal = ["confirmed", "failed", "cancelled", "refunded", "reversed", "expired"].includes(intent.state);
  const related = [
    intent.related_order_id && ["Commande", intent.related_order_id],
    intent.related_mission_id && ["Mission", intent.related_mission_id],
    intent.related_listing_id && ["Annonce", intent.related_listing_id],
    intent.related_store_id && ["Boutique", intent.related_store_id],
  ].filter(Boolean) as Array<[string, string]>;

  return (
    <>
      <SheetHeader>
        <SheetTitle className="font-mono text-sm">{intent.internal_reference}</SheetTitle>
      </SheetHeader>
      <div className="mt-3 space-y-4">
        <div className="flex items-center gap-2 flex-wrap">
          <StateChip state={intent.state} />
          <Badge variant="outline" className="text-[10px]">{providerLabel(intent.provider)}</Badge>
          <Badge variant="outline" className="text-[10px]">{intent.purpose}</Badge>
        </div>

        <dl className="text-xs grid grid-cols-[120px_1fr] gap-y-1.5">
          <dt className="text-muted-foreground">Montant</dt>
          <dd className="font-semibold">{formatGNF(intent.amount_gnf)}</dd>
          <dt className="text-muted-foreground">User</dt>
          <dd className="font-mono truncate">{intent.user_id}</dd>
          {phone && (<><dt className="text-muted-foreground">Téléphone</dt><dd className="font-mono">{maskMsisdn(phone)}</dd></>)}
          <dt className="text-muted-foreground">Réf. provider</dt>
          <dd className="font-mono">{intent.provider_reference ?? "—"}</dd>
          <dt className="text-muted-foreground">Créé</dt>
          <dd>{new Date(intent.created_at).toLocaleString("fr-FR")}</dd>
          <dt className="text-muted-foreground">Mis à jour</dt>
          <dd>{new Date(intent.updated_at).toLocaleString("fr-FR")}</dd>
          {related.map(([k, v]) => (
            <div key={k} className="contents">
              <dt className="text-muted-foreground">{k}</dt>
              <dd className="font-mono truncate">{v}</dd>
            </div>
          ))}
        </dl>

        {signals.length > 0 && (
          <div className="rounded-md border border-amber-500/30 bg-amber-500/5 p-2.5 space-y-1">
            <p className="text-[11px] font-semibold text-amber-700 uppercase tracking-wide flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" /> À vérifier
            </p>
            <ul className="text-xs text-amber-700/90 space-y-0.5 list-disc pl-4">
              {signals.map((s, idx) => <li key={idx}>{reviewSignalLabel(s)}</li>)}
            </ul>
          </div>
        )}

        <Separator />

        <div>
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground mb-2">Réconciliation</p>
          {events.length === 0 ? (
            <p className="text-xs text-muted-foreground">Aucun événement enregistré.</p>
          ) : (
            <ScrollArea className="max-h-[280px] pr-2">
              <ol className="space-y-1.5">
                {events.map((e) => (
                  <li key={e.id} className="flex items-start gap-2">
                    <span className="mt-1.5"><RecentEventDot tone={reconEventTone(e.event_type)} /></span>
                    <div className="min-w-0 flex-1">
                      <p className="text-xs font-medium">{reconEventLabel(e.event_type)}</p>
                      <p className="text-[11px] text-muted-foreground">
                        {new Date(e.created_at).toLocaleString("fr-FR")}
                        {e.provider_reference && <> · <span className="font-mono">{e.provider_reference}</span></>}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            </ScrollArea>
          )}
        </div>

        {!terminal && canSimulate && (
          <>
            <Separator />
            <div>
              <p className="text-[11px] uppercase tracking-wide text-muted-foreground mb-2">Actions admin</p>
              <div className="flex flex-wrap gap-1.5">
                <Button size="sm" variant="outline" onClick={onConfirm}>Confirmer</Button>
                <Button size="sm" variant="ghost" onClick={onFail}>Marquer échec</Button>
                {intent.provider === "orange_money" && (
                  <>
                    <Button size="sm" variant="secondary" onClick={() => onSimulate("confirmed")}>Sim confirm</Button>
                    <Button size="sm" variant="secondary" onClick={() => onSimulate("failed")}>Sim échec</Button>
                    <Button size="sm" variant="secondary" onClick={() => onSimulate("expired")}>Sim expiration</Button>
                    <Button size="sm" variant="secondary" onClick={() => onSimulate("duplicate")}>Sim doublon</Button>
                    <Button size="sm" variant="secondary" onClick={() => onSimulate("wrong_amount")}>Sim montant ≠</Button>
                  </>
                )}
              </div>
              <p className="text-[10px] text-muted-foreground mt-2">
                Les confirmations passent par <span className="font-mono">confirm_payment_intent</span> (SECURITY DEFINER). Idempotent : aucun double crédit.
              </p>
            </div>
          </>
        )}
      </div>
    </>
  );
}