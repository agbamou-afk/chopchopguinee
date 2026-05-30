import { useEffect, useMemo, useRef, useState } from "react";
import { Loader2, Check, X, AlertTriangle, FileUp, RefreshCcw, Eye, ShieldAlert, Inbox, Send, KeyRound, Clock, CheckCircle2, Wallet } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ModulePage } from "@/components/admin/ModulePage";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";
import { PaymentReceivingAccountsManager, type ReceivingAccount } from "@/components/admin/PaymentReceivingAccountsManager";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

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
  om_code_normalized?: string | null;
  receiving_account_id?: string | null;
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

type CustomerTopupRow = {
  id: string;
  reference: string;
  client_user_id: string;
  amount_gnf: number;
  status: string;
  provider: string;
  user_phone: string | null;
  created_at: string;
  expires_at: string;
  receiving_account_id: string | null;
  customer_om_code_submitted_at?: string | null;
  customer_om_code_normalized?: string | null;
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
  const [tab, setTab] = useState("demandes");
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);
  const [importing, setImporting] = useState(false);
  const [csvText, setCsvText] = useState("");
  const [importResult, setImportResult] = useState<Record<string, number | string[]> | null>(null);
  const [reviewEvent, setReviewEvent] = useState<Event | null>(null);
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [acting, setActing] = useState(false);
  const [customerTopups, setCustomerTopups] = useState<CustomerTopupRow[]>([]);
  const [customerLoading, setCustomerLoading] = useState(true);
  // Manual OM receipt entry form
  const [mTxId, setMTxId] = useState("");
  const [mAmount, setMAmount] = useState<string>("");
  const [mPhone, setMPhone] = useState("");
  const [mNote, setMNote] = useState("");
  const [mSubmitting, setMSubmitting] = useState(false);
  const [mAccountId, setMAccountId] = useState<string>("");
  const [receivingAccounts, setReceivingAccounts] = useState<ReceivingAccount[]>([]);
  const formRef = useRef<HTMLDivElement | null>(null);

  const activeOMAccounts = useMemo(
    () => receivingAccounts.filter((a) => a.provider === "orange_money" && a.is_active),
    [receivingAccounts],
  );

  useEffect(() => {
    if (!mAccountId && activeOMAccounts.length > 0) {
      setMAccountId(activeOMAccounts[0].id);
    }
  }, [activeOMAccounts, mAccountId]);

  // Load receiving accounts at page level so the customer tab can show context
  // even before the "Comptes OM" tab is opened.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("payment_receiving_accounts")
        .select("*")
        .order("updated_at", { ascending: false });
      if (!cancelled) setReceivingAccounts((data ?? []) as ReceivingAccount[]);
    })();
    return () => { cancelled = true; };
  }, []);

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("payment_provider_events")
      .select("*, om_code_normalized, receiving_account_id")
      .order("created_at", { ascending: false })
      .limit(300);
    if (error) toast.error(error.message);
    setEvents((data ?? []) as Event[]);
    setLoading(false);
  };

  const loadCustomerTopups = async () => {
    setCustomerLoading(true);
    const { data, error } = await supabase
      .from("topup_requests")
      .select("id, reference, client_user_id, amount_gnf, status, provider, user_phone, created_at, expires_at, receiving_account_id, customer_om_code_submitted_at, customer_om_code_normalized")
      .order("created_at", { ascending: false })
      .limit(300);
    if (error) toast.error(error.message);
    setCustomerTopups((data ?? []) as CustomerTopupRow[]);
    setCustomerLoading(false);
  };

  useEffect(() => { load(); loadCustomerTopups(); }, []);

  // Poll on visibility so admins see new customer requests without reload.
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === "visible") {
        void load();
        void loadCustomerTopups();
      }
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, []);

  // Polling every 15s while tab is open (financial realtime is intentionally disabled).
  useEffect(() => {
    const id = setInterval(() => {
      if (document.visibilityState === "visible") {
        void load();
        void loadCustomerTopups();
      }
    }, 15000);
    return () => clearInterval(id);
  }, []);

  // ---- Queue derivations -------------------------------------------------
  // A. Demandes clients : all pending top-up requests (no code yet OR with code).
  const qDemandes = useMemo(
    () => customerTopups.filter((t) => t.status === "pending"),
    [customerTopups],
  );
  // B. Codes clients en attente admin : customer pasted a code, not yet credited.
  const qCustomerCodeWaiting = useMemo(
    () =>
      customerTopups.filter(
        (t) =>
          !!t.customer_om_code_submitted_at &&
          !!t.customer_om_code_normalized &&
          (t.status === "pending" || t.status === "matched" || t.status === "needs_review"),
      ),
    [customerTopups],
  );
  // C. Reçus OM en attente client : admin event has code, parked, not credited.
  const qReceiptsWaiting = useMemo(
    () =>
      events.filter(
        (e) =>
          e.processing_status === "received" &&
          !e.matched_topup_request_id,
      ),
    [events],
  );
  // D. Réconciliés : credited events.
  const qReconciled = useMemo(
    () => events.filter((e) => e.processing_status === "credited"),
    [events],
  );
  // E. Conflits : events needs_review/rejected + customer topups needs_review.
  const qConflicts = useMemo(() => {
    const evs = events.filter(
      (e) => e.processing_status === "needs_review" || e.processing_status === "rejected",
    );
    return evs;
  }, [events]);
  const qTopupConflicts = useMemo(
    () => customerTopups.filter((t) => t.status === "needs_review"),
    [customerTopups],
  );
  // -----------------------------------------------------------------------

  const refreshAll = () => {
    void load();
    void loadCustomerTopups();
  };

  const prefillFromCustomerCode = (t: CustomerTopupRow) => {
    setMTxId((t.customer_om_code_normalized ?? "").toUpperCase());
    setMAmount(String(t.amount_gnf));
    if (t.receiving_account_id) setMAccountId(t.receiving_account_id);
    setTab("demandes");
    setTimeout(() => formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }), 50);
    toast.message("Formulaire pré-rempli avec le code client");
  };

  const submitManualReceipt = async () => {
    const amt = Number(mAmount);
    if (!mTxId.trim()) { toast.error("Code/Tx OM requis"); return; }
    if (!amt || amt <= 0) { toast.error("Montant invalide"); return; }
    const acct = activeOMAccounts.find((a) => a.id === mAccountId) ?? activeOMAccounts[0];
    if (!acct) { toast.error("Configurez un numéro de réception OM actif"); return; }
    setMSubmitting(true);
    const { data: inserted, error } = await supabase
      .from("payment_provider_events")
      .insert({
        provider: "orange_money",
        event_type: "payment.received",
        provider_transaction_id: mTxId.trim().toUpperCase(),
        payer_phone: mPhone.trim() || null,
        amount_gnf: amt,
        status: "successful",
        raw_payload: {
          source: "admin_manual_entry",
          note: mNote || null,
          receiving_account_id: acct.id,
          receiving_phone: acct.phone_e164,
          receiving_label: acct.label,
        },
      })
      .select("id")
      .single();
    if (error) { setMSubmitting(false); toast.error(error.message); return; }
    // Trigger the existing auto-match (idempotent; secure RPC).
    const { error: mErr } = await supabase.rpc("om_auto_match", { p_event_id: inserted.id });
    setMSubmitting(false);
    if (mErr) { toast.error(mErr.message); return; }
    // Try to interpret RPC result, but be defensive about return shape.
    toast.success("Reçu enregistré · matching lancé");
    setMTxId(""); setMAmount(""); setMPhone(""); setMNote("");
    refreshAll();
  };

  const cancelTopup = async (topupId: string) => {
    setActing(true);
    const { error } = await supabase.rpc("wallet_topup_admin_cancel" as never, {
      p_topup_id: topupId,
      p_reason: "Annulé manuellement par admin",
    } as never);
    setActing(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Demande annulée");
    void loadCustomerTopups();
  };

  const expireTopup = async (topupId: string) => {
    if (!confirm("Marquer cette demande comme expirée ? Cette action est journalisée.")) return;
    setActing(true);
    const { error } = await supabase.rpc("wallet_topup_admin_mark_expired" as never, {
      p_topup_id: topupId,
      p_reason: "Marquée expirée par admin",
    } as never);
    setActing(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Demande marquée expirée");
    void loadCustomerTopups();
  };

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
        <TabsList className="grid w-full grid-cols-2 md:grid-cols-7 h-auto">
          <TabsTrigger value="demandes" className="text-[11px]">
            Demandes <Badge variant="outline" className="ml-1 text-[9px]">{qDemandes.length}</Badge>
          </TabsTrigger>
          <TabsTrigger value="code_waiting" className="text-[11px]">
            Codes clients <Badge variant="outline" className="ml-1 text-[9px]">{qCustomerCodeWaiting.length}</Badge>
          </TabsTrigger>
          <TabsTrigger value="receipts_waiting" className="text-[11px]">
            Reçus en attente <Badge variant="outline" className="ml-1 text-[9px]">{qReceiptsWaiting.length}</Badge>
          </TabsTrigger>
          <TabsTrigger value="reconciled" className="text-[11px]">
            Réconciliés <Badge variant="outline" className="ml-1 text-[9px]">{qReconciled.length}</Badge>
          </TabsTrigger>
          <TabsTrigger value="conflicts" className="text-[11px]">
            Conflits <Badge variant="outline" className="ml-1 text-[9px]">{qConflicts.length + qTopupConflicts.length}</Badge>
          </TabsTrigger>
          <TabsTrigger value="accounts" className="text-[11px]">Comptes OM</TabsTrigger>
          <TabsTrigger value="import" className="text-[11px]">Import CSV</TabsTrigger>
        </TabsList>

        <TabsContent value="demandes" className="mt-4 space-y-4">
          {activeOMAccounts.length === 0 && (
            <Card className="p-3 bg-destructive/10 border-destructive/30">
              <div className="flex items-start gap-2">
                <AlertTriangle className="w-4 h-4 text-destructive shrink-0 mt-0.5" />
                <p className="text-xs">
                  Aucun numéro de réception Orange Money actif. La recharge OM est désactivée côté client.
                  Configurez un numéro dans l'onglet « Comptes OM ».
                </p>
              </div>
            </Card>
          )}
          {/* Manual OM receipt entry */}
          <Card ref={formRef} className="p-4 space-y-3">
            <div className="flex items-center gap-2">
              <Send className="w-4 h-4 text-primary" />
              <p className="font-semibold text-sm">Saisie manuelle d'un reçu Orange Money</p>
            </div>
            <p className="text-xs text-muted-foreground">
              Saisissez ici le code de confirmation reçu sur le téléphone CHOPCHOP. Le système tentera automatiquement de rapprocher avec une demande client en attente du même montant.
            </p>
            <div>
              <Label className="text-[11px]">Numéro CHOPCHOP qui a reçu</Label>
              <Select value={mAccountId} onValueChange={setMAccountId}>
                <SelectTrigger>
                  <SelectValue placeholder={activeOMAccounts.length === 0 ? "Aucun numéro actif" : "Choisir un numéro"} />
                </SelectTrigger>
                <SelectContent>
                  {activeOMAccounts.map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      {a.label} · {a.phone_e164}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-2">
              <div>
                <Label htmlFor="m-tx" className="text-[11px]">Code OM</Label>
                <Input id="m-tx" value={mTxId} onChange={(e) => setMTxId(e.target.value)} placeholder="ABC123XYZ" className="font-mono" />
              </div>
              <div>
                <Label htmlFor="m-amt" className="text-[11px]">Montant reçu (GNF)</Label>
                <Input id="m-amt" inputMode="numeric" value={mAmount} onChange={(e) => setMAmount(e.target.value.replace(/\D/g, ""))} placeholder="50000" />
              </div>
              <div>
                <Label htmlFor="m-ph" className="text-[11px]">Téléphone payeur (optionnel)</Label>
                <Input id="m-ph" value={mPhone} onChange={(e) => setMPhone(e.target.value)} placeholder="+224 6XX XX XX XX" />
              </div>
              <div>
                <Label htmlFor="m-note" className="text-[11px]">Note (optionnelle)</Label>
                <Input id="m-note" value={mNote} onChange={(e) => setMNote(e.target.value)} placeholder="Compte OM principal" />
              </div>
            </div>
            <div className="flex justify-end">
              <Button onClick={submitManualReceipt} disabled={mSubmitting || !mTxId.trim() || !mAmount || activeOMAccounts.length === 0}>
                {mSubmitting ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Send className="w-4 h-4 mr-2" />}
                Ajouter le reçu
              </Button>
            </div>
          </Card>

          {/* Customer pending requests */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Inbox className="w-4 h-4" />
              <p className="text-sm font-semibold">Demandes clients</p>
            </div>
            <Button variant="outline" size="sm" onClick={refreshAll} disabled={customerLoading}>
              <RefreshCcw className={`w-4 h-4 mr-1 ${customerLoading ? "animate-spin" : ""}`} /> Rafraîchir
            </Button>
          </div>
          <Card className="p-0 overflow-hidden">
            {customerLoading ? (
              <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
            ) : qDemandes.length === 0 ? (
              <div className="p-12 text-center text-muted-foreground text-sm">Aucune demande client.</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left">
                    <tr>
                      <th className="p-3">Créée</th>
                      <th className="p-3">Référence</th>
                      <th className="p-3">Téléphone client</th>
                      <th className="p-3">Compte réception</th>
                      <th className="p-3 text-right">Montant</th>
                      <th className="p-3">Code client</th>
                      <th className="p-3">Expire</th>
                      <th className="p-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                      {qDemandes.map((t) => {
                       const ra = receivingAccounts.find((a) => a.id === t.receiving_account_id);
                       const hasCode = !!t.customer_om_code_submitted_at;
                       const isStale = new Date(t.expires_at).getTime() < Date.now()
                         || (Date.now() - new Date(t.created_at).getTime()) > 24 * 3600 * 1000;
                       return (
                      <tr key={t.id} className="border-t">
                        <td className="p-3 text-xs whitespace-nowrap">{fmtDate(t.created_at)}</td>
                        <td className="p-3 font-mono text-xs">{t.reference}</td>
                        <td className="p-3 text-xs">{t.user_phone ?? "—"}</td>
                        <td className="p-3 text-xs">
                          {ra ? `${ra.label} · ${ra.phone_e164}` : "—"}
                        </td>
                        <td className="p-3 text-right font-medium">{formatGNF(t.amount_gnf)}</td>
                        <td className="p-3">
                          {hasCode ? (
                            <Badge className="text-[10px] bg-primary/15 text-primary border-primary/30">Code client reçu</Badge>
                          ) : (
                            <Badge variant="outline" className="text-[10px]">Code non reçu</Badge>
                          )}
                        </td>
                        <td className="p-3 text-xs whitespace-nowrap">{fmtDate(t.expires_at)}</td>
                        <td className="p-3 text-right">
                          {hasCode ? (
                            <Badge variant="outline" className="text-[10px]">Vérification en cours</Badge>
                          ) : isStale ? (
                            <Button size="sm" variant="ghost" disabled={acting} onClick={() => expireTopup(t.id)}>
                              <Clock className="w-3.5 h-3.5 mr-1" /> Marquer expirée
                            </Button>
                          ) : (
                            <Button size="sm" variant="ghost" disabled={acting} onClick={() => cancelTopup(t.id)}>
                              <X className="w-3.5 h-3.5 mr-1" /> Annuler
                            </Button>
                          )}
                        </td>
                      </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
          <p className="text-[11px] text-muted-foreground">
            Le crédit du wallet est effectué automatiquement par le backend lorsqu'un reçu OM correspond au montant et à une demande client active. Aucun crédit manuel depuis l'interface.
          </p>
        </TabsContent>

        {/* B. Codes clients en attente admin */}
        <TabsContent value="code_waiting" className="mt-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <KeyRound className="w-4 h-4" />
              <p className="text-sm font-semibold">Codes clients en attente admin</p>
            </div>
            <Button variant="outline" size="sm" onClick={refreshAll}>
              <RefreshCcw className="w-4 h-4 mr-1" /> Rafraîchir
            </Button>
          </div>
          <Card className="p-0 overflow-hidden">
            {customerLoading ? (
              <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
            ) : qCustomerCodeWaiting.length === 0 ? (
              <div className="p-12 text-center text-muted-foreground text-sm">Aucun code client en attente.</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left">
                    <tr>
                      <th className="p-3">Soumis</th>
                      <th className="p-3">Client</th>
                      <th className="p-3">Code OM</th>
                      <th className="p-3 text-right">Montant</th>
                      <th className="p-3">Compte réception</th>
                      <th className="p-3">Statut</th>
                      <th className="p-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {qCustomerCodeWaiting.map((t) => {
                      const ra = receivingAccounts.find((a) => a.id === t.receiving_account_id);
                      return (
                        <tr key={t.id} className="border-t">
                          <td className="p-3 text-xs whitespace-nowrap">
                            {t.customer_om_code_submitted_at ? fmtDate(t.customer_om_code_submitted_at) : "—"}
                          </td>
                          <td className="p-3 text-xs">{t.user_phone ?? "—"}</td>
                          <td className="p-3 font-mono text-xs">{t.customer_om_code_normalized ?? "—"}</td>
                          <td className="p-3 text-right font-medium">{formatGNF(t.amount_gnf)}</td>
                          <td className="p-3 text-xs">{ra ? `${ra.label} · ${ra.phone_e164}` : "—"}</td>
                          <td className="p-3">
                            <Badge variant="outline" className="text-[10px]">
                              {t.status === "matched" ? "Code client reçu" : t.status === "needs_review" ? "À vérifier" : "En attente reçu OM"}
                            </Badge>
                          </td>
                          <td className="p-3 text-right">
                            <Button size="sm" onClick={() => prefillFromCustomerCode(t)}>
                              <Send className="w-3.5 h-3.5 mr-1" /> Entrer reçu OM
                            </Button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </TabsContent>

        {/* C. Reçus OM en attente client */}
        <TabsContent value="receipts_waiting" className="mt-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Clock className="w-4 h-4" />
              <p className="text-sm font-semibold">Reçus OM en attente client</p>
            </div>
            <Button variant="outline" size="sm" onClick={refreshAll}>
              <RefreshCcw className="w-4 h-4 mr-1" /> Rafraîchir
            </Button>
          </div>
          <Card className="p-0 overflow-hidden">
            {loading ? (
              <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
            ) : qReceiptsWaiting.length === 0 ? (
              <div className="p-12 text-center text-muted-foreground text-sm">Aucun reçu OM en attente client.</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left">
                    <tr>
                      <th className="p-3">Reçu le</th>
                      <th className="p-3">Code OM</th>
                      <th className="p-3 text-right">Montant</th>
                      <th className="p-3">Payeur</th>
                      <th className="p-3">Compte réception</th>
                      <th className="p-3">Note</th>
                      <th className="p-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {qReceiptsWaiting.map((e) => {
                      const ra = receivingAccounts.find((a) => a.id === (e.receiving_account_id ?? (e.raw_payload as { receiving_account_id?: string })?.receiving_account_id));
                      return (
                        <tr key={e.id} className="border-t">
                          <td className="p-3 text-xs whitespace-nowrap">{fmtDate(e.created_at)}</td>
                          <td className="p-3 font-mono text-xs">{e.om_code_normalized ?? e.provider_transaction_id}</td>
                          <td className="p-3 text-right font-medium">{formatGNF(e.amount_gnf)}</td>
                          <td className="p-3 text-xs">{e.payer_phone ?? "—"}</td>
                          <td className="p-3 text-xs">{ra ? `${ra.label} · ${ra.phone_e164}` : "—"}</td>
                          <td className="p-3 text-xs text-muted-foreground max-w-[180px] truncate">{e.notes ?? "—"}</td>
                          <td className="p-3 text-right">
                            <Button size="sm" variant="ghost" onClick={() => openReview(e)}>
                              <Eye className="w-3.5 h-3.5 mr-1" /> Détails
                            </Button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </TabsContent>

        {/* D. Réconciliés */}
        <TabsContent value="reconciled" className="mt-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4 text-success" />
              <p className="text-sm font-semibold">Réconciliés</p>
            </div>
            <Button variant="outline" size="sm" onClick={refreshAll}>
              <RefreshCcw className="w-4 h-4 mr-1" /> Rafraîchir
            </Button>
          </div>
          <Card className="p-0 overflow-hidden">
            {loading ? (
              <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
            ) : qReconciled.length === 0 ? (
              <div className="p-12 text-center text-muted-foreground text-sm">Aucune recharge réconciliée.</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left">
                    <tr>
                      <th className="p-3">Crédité le</th>
                      <th className="p-3">Code OM</th>
                      <th className="p-3">Payeur</th>
                      <th className="p-3 text-right">Montant</th>
                      <th className="p-3">Compte</th>
                      <th className="p-3">Statut</th>
                    </tr>
                  </thead>
                  <tbody>
                    {qReconciled.map((e) => {
                      const ra = receivingAccounts.find((a) => a.id === (e.receiving_account_id ?? (e.raw_payload as { receiving_account_id?: string })?.receiving_account_id));
                      return (
                        <tr key={e.id} className="border-t">
                          <td className="p-3 text-xs whitespace-nowrap">{e.processed_at ? fmtDate(e.processed_at) : fmtDate(e.created_at)}</td>
                          <td className="p-3 font-mono text-xs">{e.om_code_normalized ?? e.provider_transaction_id}</td>
                          <td className="p-3 text-xs">{e.payer_phone ?? "—"}</td>
                          <td className="p-3 text-right font-medium">{formatGNF(e.amount_gnf)}</td>
                          <td className="p-3 text-xs">{ra ? `${ra.label} · ${ra.phone_e164}` : "—"}</td>
                          <td className="p-3">
                            <Badge className="text-[10px] bg-success/15 text-success border-success/30">
                              <Wallet className="w-3 h-3 mr-1" /> Crédité
                            </Badge>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </TabsContent>

        {/* E. Conflits / à vérifier */}
        <TabsContent value="conflicts" className="mt-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <ShieldAlert className="w-4 h-4 text-destructive" />
              <p className="text-sm font-semibold">Conflits / à vérifier</p>
            </div>
            <Button variant="outline" size="sm" onClick={refreshAll}>
              <RefreshCcw className="w-4 h-4 mr-1" /> Rafraîchir
            </Button>
          </div>
          <Card className="p-0 overflow-hidden">
            {loading ? (
              <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
            ) : qConflicts.length === 0 && qTopupConflicts.length === 0 ? (
              <div className="p-12 text-center text-muted-foreground text-sm">Aucun conflit à vérifier.</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left">
                    <tr>
                      <th className="p-3">Source</th>
                      <th className="p-3">Date</th>
                      <th className="p-3">Code OM</th>
                      <th className="p-3 text-right">Montant</th>
                      <th className="p-3">Raison</th>
                      <th className="p-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {qConflicts.map((e) => (
                      <tr key={`e-${e.id}`} className="border-t">
                        <td className="p-3"><Badge variant="outline" className="text-[10px]">Reçu admin</Badge></td>
                        <td className="p-3 text-xs whitespace-nowrap">{fmtDate(e.created_at)}</td>
                        <td className="p-3 font-mono text-xs">{e.om_code_normalized ?? e.provider_transaction_id}</td>
                        <td className="p-3 text-right font-medium">{formatGNF(e.amount_gnf)}</td>
                        <td className="p-3 text-xs text-muted-foreground max-w-[220px] truncate">{e.notes ?? STATUS_LABEL[e.processing_status] ?? e.processing_status}</td>
                        <td className="p-3 text-right">
                          <Button size="sm" variant="ghost" onClick={() => openReview(e)}>
                            <Eye className="w-3.5 h-3.5 mr-1" /> Détails
                          </Button>
                        </td>
                      </tr>
                    ))}
                    {qTopupConflicts.map((t) => (
                      <tr key={`t-${t.id}`} className="border-t">
                        <td className="p-3"><Badge variant="outline" className="text-[10px]">Demande client</Badge></td>
                        <td className="p-3 text-xs whitespace-nowrap">{fmtDate(t.created_at)}</td>
                        <td className="p-3 font-mono text-xs">{t.customer_om_code_normalized ?? "—"}</td>
                        <td className="p-3 text-right font-medium">{formatGNF(t.amount_gnf)}</td>
                        <td className="p-3 text-xs text-muted-foreground">À vérifier</td>
                        <td className="p-3 text-right">
                          <span className="text-[11px] text-muted-foreground">À traiter manuellement</span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </TabsContent>

        <TabsContent value="accounts" className="mt-4">
          <PaymentReceivingAccountsManager onChange={setReceivingAccounts} />
        </TabsContent>

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