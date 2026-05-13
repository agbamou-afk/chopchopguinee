import { useEffect, useMemo, useState } from "react";
import { Loader2, Check, X, AlertTriangle, FileUp, RefreshCcw, Eye, ShieldAlert } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ModulePage } from "@/components/admin/ModulePage";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";

type Event = {
  id: string;
  provider: string;
  provider_transaction_id: string;
  payer_phone: string | null;
  amount_gnf: number;
  status: string;
  processing_status: string;
  matched_user_id: string | null;
  matched_topup_request_id: string | null;
  match_confidence: number | null;
  notes: string | null;
  created_at: string;
  processed_at: string | null;
  raw_payload: Record<string, unknown>;
};

type Candidate = {
  topup_id: string;
  reference: string;
  client_user_id: string;
  client_phone: string | null;
  client_name: string | null;
  amount_gnf: number;
  created_at: string;
  expires_at: string;
  status: string;
  amount_match: boolean;
  phone_match: boolean;
};

const STATUS_LABEL: Record<string, string> = {
  received: "Reçu",
  credited: "Crédité",
  needs_review: "À revoir",
  rejected: "Rejeté",
  expired: "Expiré",
  suspicious: "Suspect",
};

function fmtDate(iso: string) {
  return new Date(iso).toLocaleString("fr-FR", {
    day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

export default function WalletReconciliation() {
  const [tab, setTab] = useState("auto");
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);
  const [importing, setImporting] = useState(false);
  const [csvText, setCsvText] = useState("");
  const [importResult, setImportResult] = useState<Record<string, number | string[]> | null>(null);
  const [reviewEvent, setReviewEvent] = useState<Event | null>(null);
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [acting, setActing] = useState(false);

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("payment_provider_events")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(300);
    if (error) toast.error(error.message);
    setEvents((data ?? []) as Event[]);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const filtered = useMemo(() => {
    switch (tab) {
      case "auto": return events.filter((e) => e.processing_status === "credited");
      case "pending": return events.filter((e) => e.processing_status === "received");
      case "review": return events.filter((e) => e.processing_status === "needs_review");
      case "expired": return events.filter((e) => e.processing_status === "rejected" && (e.notes ?? "").includes("expired"));
      case "suspicious": return events.filter((e) => e.processing_status === "rejected" || (e.notes ?? "").includes("suspect"));
      default: return events;
    }
  }, [events, tab]);

  const openReview = async (e: Event) => {
    setReviewEvent(e);
    setCandidates([]);
    const { data, error } = await supabase.rpc("om_pending_topups_for_event", { p_event_id: e.id });
    if (error) toast.error(error.message);
    setCandidates((data ?? []) as Candidate[]);
  };

  const approve = async (topupId: string) => {
    if (!reviewEvent) return;
    setActing(true);
    const { error } = await supabase.rpc("wallet_topup_om_credit", {
      p_event_id: reviewEvent.id, p_topup_request_id: topupId,
    });
    setActing(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Recharge créditée");
    setReviewEvent(null);
    load();
  };

  const reject = async (note: string) => {
    if (!reviewEvent) return;
    setActing(true);
    const { error } = await supabase
      .from("payment_provider_events")
      .update({ processing_status: "rejected", notes: note, processed_at: new Date().toISOString() })
      .eq("id", reviewEvent.id);
    setActing(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Événement rejeté");
    setReviewEvent(null);
    load();
  };

  const runImport = async () => {
    if (!csvText.trim()) { toast.error("Collez le contenu CSV"); return; }
    setImporting(true); setImportResult(null);
    const { data, error } = await supabase.functions.invoke("om-import-csv", {
      body: { csv: csvText },
    });
    setImporting(false);
    if (error) { toast.error(error.message); return; }
    setImportResult(((data as { summary?: Record<string, number | string[]> })?.summary) ?? {});
    toast.success("Import terminé");
    load();
  };

  const handleFile = async (f: File) => {
    const text = await f.text();
    setCsvText(text);
  };

  return (
    <ModulePage module="wallet" title="Réconciliation Orange Money" subtitle="Suivi des paiements et rapprochement des recharges">
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="grid w-full grid-cols-6">
          <TabsTrigger value="auto">Auto-créditées</TabsTrigger>
          <TabsTrigger value="pending">En attente</TabsTrigger>
          <TabsTrigger value="review">À revoir</TabsTrigger>
          <TabsTrigger value="expired">Expirées</TabsTrigger>
          <TabsTrigger value="suspicious">Suspectes</TabsTrigger>
          <TabsTrigger value="import">Import CSV</TabsTrigger>
        </TabsList>

        {(["auto","pending","review","expired","suspicious"] as const).map((k) => (
          <TabsContent key={k} value={k} className="mt-4">
            <div className="flex justify-end mb-2">
              <Button variant="outline" size="sm" onClick={load} disabled={loading}>
                <RefreshCcw className={`w-4 h-4 mr-1 ${loading ? "animate-spin" : ""}`} /> Rafraîchir
              </Button>
            </div>
            <Card className="p-0 overflow-hidden">
              {loading ? (
                <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
              ) : filtered.length === 0 ? (
                <div className="p-12 text-center text-muted-foreground text-sm">Aucun élément.</div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead className="bg-muted/50 text-left">
                      <tr>
                        <th className="p-3">Date</th>
                        <th className="p-3">Tx ID</th>
                        <th className="p-3">Téléphone</th>
                        <th className="p-3 text-right">Montant</th>
                        <th className="p-3">Statut</th>
                        <th className="p-3">Notes</th>
                        <th className="p-3 text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filtered.map((e) => (
                        <tr key={e.id} className="border-t">
                          <td className="p-3 text-xs whitespace-nowrap">{fmtDate(e.created_at)}</td>
                          <td className="p-3 font-mono text-xs">{e.provider_transaction_id}</td>
                          <td className="p-3 text-xs">{e.payer_phone ?? "—"}</td>
                          <td className="p-3 text-right font-medium">{formatGNF(e.amount_gnf)}</td>
                          <td className="p-3">
                            <Badge variant="outline" className="text-[10px]">{STATUS_LABEL[e.processing_status] ?? e.processing_status}</Badge>
                          </td>
                          <td className="p-3 text-xs text-muted-foreground max-w-[180px] truncate">{e.notes ?? "—"}</td>
                          <td className="p-3 text-right">
                            <Button size="sm" variant="ghost" onClick={() => openReview(e)}>
                              <Eye className="w-3.5 h-3.5 mr-1" /> Détails
                            </Button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>
          </TabsContent>
        ))}

        <TabsContent value="import" className="mt-4">
          <Card className="p-5 space-y-3">
            <div>
              <p className="font-semibold text-sm">Import CSV — relevé Orange Money</p>
              <p className="text-xs text-muted-foreground">
                Colonnes attendues (libres, casse insensible) : <span className="font-mono">transaction_id, payer_phone, amount_gnf, status</span>.
                Les doublons sont ignorés. Les lignes valides sont importées et passent par <span className="font-mono">om_auto_match</span>.
              </p>
            </div>
            <input type="file" accept=".csv,text/csv"
              onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); }}
              className="block text-xs" />
            <Textarea
              placeholder="Ou collez le CSV ici…"
              value={csvText} onChange={(e) => setCsvText(e.target.value)}
              rows={8} className="font-mono text-xs" />
            <div className="flex gap-2">
              <Button onClick={runImport} disabled={importing || !csvText.trim()}>
                {importing ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <FileUp className="w-4 h-4 mr-2" />}
                Importer
              </Button>
              <Button variant="outline" onClick={() => { setCsvText(""); setImportResult(null); }}>Effacer</Button>
            </div>
            {importResult && (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mt-2">
                {Object.entries(importResult).filter(([, v]) => typeof v === "number").map(([k, v]) => (
                  <div key={k} className="rounded-lg bg-muted/50 p-3">
                    <p className="text-[11px] uppercase tracking-wider text-muted-foreground">{k}</p>
                    <p className="text-xl font-bold">{v as number}</p>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </TabsContent>
      </Tabs>

      <Dialog open={!!reviewEvent} onOpenChange={(o) => !o && setReviewEvent(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Détails événement Orange Money</DialogTitle>
            <DialogDescription>Transaction reçue du fournisseur — choisir une action.</DialogDescription>
          </DialogHeader>
          {reviewEvent && (
            <div className="space-y-3 text-sm">
              <div className="grid grid-cols-2 gap-3">
                <Info label="Tx ID" value={reviewEvent.provider_transaction_id} mono />
                <Info label="Statut fournisseur" value={reviewEvent.status} />
                <Info label="Téléphone payeur" value={reviewEvent.payer_phone ?? "—"} />
                <Info label="Montant" value={formatGNF(reviewEvent.amount_gnf)} />
                <Info label="Reçu le" value={fmtDate(reviewEvent.created_at)} />
                <Info label="Confiance" value={reviewEvent.match_confidence ? `${Math.round(reviewEvent.match_confidence * 100)}%` : "—"} />
              </div>
              {reviewEvent.notes && (
                <div className="rounded-lg bg-muted/50 p-2 text-xs flex items-start gap-2">
                  <ShieldAlert className="w-3.5 h-3.5 text-secondary-foreground mt-0.5" />
                  <span>{reviewEvent.notes}</span>
                </div>
              )}
              <div>
                <p className="font-semibold text-xs uppercase tracking-wider mb-2">Recharges candidates</p>
                {candidates.length === 0 ? (
                  <div className="p-4 text-center text-xs text-muted-foreground rounded-lg bg-muted/40">
                    Aucune demande de recharge en attente correspondante.
                  </div>
                ) : (
                  <div className="space-y-1.5 max-h-60 overflow-y-auto">
                    {candidates.map((c) => (
                      <div key={c.topup_id} className="flex items-center justify-between rounded-lg border p-2.5">
                        <div className="min-w-0">
                          <p className="font-mono text-xs">{c.reference}</p>
                          <p className="text-xs text-muted-foreground truncate">
                            {c.client_name ?? "Sans nom"} · {c.client_phone ?? "—"} · {formatGNF(c.amount_gnf)}
                          </p>
                          <div className="flex gap-1 mt-0.5">
                            {c.amount_match && <Badge variant="outline" className="text-[9px]">Montant ✓</Badge>}
                            {c.phone_match && <Badge variant="outline" className="text-[9px]">Téléphone ✓</Badge>}
                          </div>
                        </div>
                        <Button size="sm" disabled={acting} onClick={() => approve(c.topup_id)}>
                          <Check className="w-3.5 h-3.5 mr-1" /> Créditer
                        </Button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" disabled={acting} onClick={() => reject("Rejeté manuellement par admin")}>
              <X className="w-4 h-4 mr-1" /> Rejeter
            </Button>
            <Button variant="outline" disabled={acting} onClick={() => reject("Marqué suspect par admin")}>
              <AlertTriangle className="w-4 h-4 mr-1" /> Marquer suspect
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </ModulePage>
  );
}

function Info({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="rounded-lg bg-muted/40 p-2">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className={`text-xs ${mono ? "font-mono" : "font-medium"}`}>{value}</p>
    </div>
  );
}