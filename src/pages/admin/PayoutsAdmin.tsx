import { useState } from "react";
import { Loader2, ShieldAlert, RefreshCw, CalendarClock, Send, XCircle } from "lucide-react";
import { Card } from "@/components/ui/card";
import { ModulePage } from "@/components/admin/ModulePage";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";
import {
  usePayoutQueue, recordPayoutEvidence, reconcilePayoutEvidence, rejectPayoutOrder,
  generateSettlementSchedule, confirmManualOmPayout, isManualOmMerchantPayout,
  MANUAL_OM_REFERENCE_MIN_LENGTH, type PayoutQueueBucket, type PayoutQueueItem,
} from "@/lib/finance/payouts";

const BUCKETS: { key: PayoutQueueBucket; label: string }[] = [
  { key: "requested", label: "Demandes" },
  { key: "awaiting_proof", label: "Preuve attendue" },
  { key: "manual_review", label: "Revue manuelle" },
  { key: "settled", label: "Réglés" },
  { key: "rejected", label: "Rejetés" },
];

const EVIDENCE_TONE: Record<string, string> = {
  recorded: "bg-secondary/30 text-foreground",
  evidence_incomplete: "bg-warning/15 text-warning",
  mismatch: "bg-destructive/15 text-destructive",
  reconciled: "bg-success/15 text-success",
  rejected: "bg-muted text-muted-foreground",
};

/**
 * Slice 11 — Finance payout console.
 *
 * There is NO "mark as paid" action here. A payout only becomes settled when
 * exact outbound provider evidence is recorded and the server reconciles it.
 * Every amount shown comes from `finance_payout_queue`.
 */
function QueueTable({ bucket }: { bucket: PayoutQueueBucket }) {
  const { items, loading, error, refresh } = usePayoutQueue(bucket);
  const [evidenceFor, setEvidenceFor] = useState<PayoutQueueItem | null>(null);
  const [manualFor, setManualFor] = useState<PayoutQueueItem | null>(null);
  const [manualRef, setManualRef] = useState("");
  const [attested, setAttested] = useState(false);
  const [rejectFor, setRejectFor] = useState<PayoutQueueItem | null>(null);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ reference: "", msisdn: "", amount: "", status: "success" });
  const [reason, setReason] = useState("");

  const openEvidence = (it: PayoutQueueItem) => {
    setForm({ reference: "", msisdn: it.destination_msisdn, amount: String(it.recipient_net_gnf), status: "success" });
    setEvidenceFor(it);
  };

  const submitEvidence = async () => {
    if (!evidenceFor) return;
    setBusy(true);
    const res = await recordPayoutEvidence({
      payoutOrderId: evidenceFor.payout_order_id,
      provider: evidenceFor.provider,
      providerReference: form.reference.trim(),
      recipientMsisdn: form.msisdn.trim(),
      amountGnf: Number(form.amount.replace(/[^\d]/g, "")) || 0,
      providerStatus: form.status.trim(),
      environment: evidenceFor.environment === "production" ? "production" : "sandbox",
      transferredAt: new Date().toISOString(),
    });
    setBusy(false);
    if (res.ok === false) { toast.error(res.error); return; }
    const status = String((res.result as { status?: string }).status ?? "");
    if (status === "settled") toast.success("Règlement réconcilié et comptabilisé.");
    else toast.warning(`Preuve enregistrée sans mouvement : ${status}`);
    setEvidenceFor(null);
    void refresh();
  };

  const openManual = (it: PayoutQueueItem) => {
    setManualRef(""); setAttested(false); setManualFor(it);
  };

  const submitManual = async () => {
    if (!manualFor) return;
    setBusy(true);
    const res = await confirmManualOmPayout({
      payoutOrderId: manualFor.payout_order_id,
      providerReference: manualRef.trim(),
      attestation: attested,
      transferredAt: new Date().toISOString(),
    });
    setBusy(false);
    if (!res.ok) { toast.error(res.error); return; }
    const status = String((res.result as { status?: string }).status ?? "");
    if (status === "settled") toast.success("Virement Orange Money attesté et règlement comptabilisé.");
    else if (status === "already_settled") toast.info("Ce versement était déjà réglé. Aucun mouvement.");
    else toast.warning(`Preuve attestée sans règlement : ${status}`);
    setManualFor(null); setManualRef(""); setAttested(false);
    void refresh();
  };

  const submitReject = async () => {
    if (!rejectFor) return;
    setBusy(true);
    const res = await rejectPayoutOrder(rejectFor.payout_order_id, reason.trim());
    setBusy(false);
    if (!res.ok) { toast.error(res.error); return; }
    toast.success("Réservation libérée. Aucun argent n'a bougé.");
    setRejectFor(null); setReason("");
    void refresh();
  };

  if (loading) {
    return <div className="flex items-center gap-2 p-6 text-muted-foreground"><Loader2 className="w-4 h-4 animate-spin" /> Chargement…</div>;
  }
  if (error) {
    return <Card className="p-6 text-sm text-destructive">{error}</Card>;
  }
  if (items.length === 0) {
    return <Card className="p-6 text-sm text-muted-foreground">Aucun élément dans cette file.</Card>;
  }

  return (
    <div className="space-y-3">
      {items.map((it) => (
        <Card key={it.payout_order_id} className="p-4 space-y-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="font-semibold text-foreground truncate">{it.store_name ?? it.party_type}</p>
              <p className="text-xs text-muted-foreground">
                {it.destination_msisdn} · {it.provider} · {it.environment}
              </p>
            </div>
            <div className="text-right">
              <p className="font-bold tabular-nums text-foreground">{formatGNF(it.requested_principal_gnf)}</p>
              <p className="text-[11px] text-muted-foreground tabular-nums">
                net {formatGNF(it.recipient_net_gnf)} · frais {formatGNF(it.provider_fee_gnf)} ({it.fee_borne_by === "platform" ? "plateforme" : "bénéficiaire"})
              </p>
            </div>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-[11px]">
            <div className="rounded-lg bg-muted/40 p-2">
              <p className="text-muted-foreground">Réservé</p>
              <p className="font-bold tabular-nums">{formatGNF(it.reservation_gnf)}</p>
            </div>
            <div className="rounded-lg bg-muted/40 p-2">
              <p className="text-muted-foreground">Débit marchand</p>
              <p className="font-bold tabular-nums">{formatGNF(it.merchant_liability_debit_gnf)}</p>
            </div>
            <div className="rounded-lg bg-muted/40 p-2">
              <p className="text-muted-foreground">Réglé</p>
              <p className="font-bold tabular-nums">{formatGNF(it.settled_gnf)}</p>
            </div>
            <div className="rounded-lg bg-muted/40 p-2">
              <p className="text-muted-foreground">Statut</p>
              <p className="font-bold">{it.status}</p>
            </div>
          </div>

          {it.evidence.length > 0 && (
            <div className="space-y-1">
              {it.evidence.map((e) => (
                <div key={e.evidence_id} className="flex items-center justify-between gap-2 text-[11px]">
                  <span className="font-mono truncate">{e.provider_reference}</span>
                  <span className="flex items-center gap-2">
                    <span className={`px-2 py-0.5 rounded-full ${EVIDENCE_TONE[e.state] ?? "bg-muted"}`}>
                      {e.state}{e.reason ? ` · ${e.reason}` : ""}
                    </span>
                    {e.state === "recorded" && (
                      <Button size="sm" variant="outline" onClick={async () => {
                        const res = await reconcilePayoutEvidence(e.evidence_id);
                        if (!res.ok) toast.error(res.error); else { toast.success("Réconciliation relancée."); void refresh(); }
                      }}>
                        <RefreshCw className="w-3 h-3" />
                      </Button>
                    )}
                  </span>
                </div>
              ))}
            </div>
          )}

          {it.status !== "settled" && it.status !== "rejected" && it.status !== "released" && (
            <div className="flex gap-2">
              <Button size="sm" onClick={() => openEvidence(it)}>
                <Send className="w-4 h-4 mr-1" /> Enregistrer la preuve
              </Button>
              <Button size="sm" variant="outline" onClick={() => setRejectFor(it)}>
                <XCircle className="w-4 h-4 mr-1" /> Rejeter / libérer
              </Button>
            </div>
          )}
          {it.reject_reason && (
            <p className="text-[11px] text-destructive">Motif : {it.reject_reason}</p>
          )}
        </Card>
      ))}

      <Dialog open={!!evidenceFor} onOpenChange={(o) => !o && setEvidenceFor(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Preuve de virement sortant</DialogTitle>
            <DialogDescription>
              Le serveur ne règle que si la référence, le numéro, le montant, le statut fournisseur
              et l'environnement correspondent exactement. Sinon le dossier part en revue manuelle.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div><Label>Référence fournisseur</Label>
              <Input value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} /></div>
            <div><Label>Numéro bénéficiaire</Label>
              <Input value={form.msisdn} onChange={(e) => setForm({ ...form, msisdn: e.target.value })} /></div>
            <div><Label>Montant transféré (GNF)</Label>
              <Input inputMode="numeric" value={form.amount}
                     onChange={(e) => setForm({ ...form, amount: e.target.value.replace(/[^\d]/g, "") })} /></div>
            <div><Label>Statut fournisseur</Label>
              <Input value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button onClick={submitEvidence} disabled={busy || form.reference.trim().length < 4}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Soumettre la preuve"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!rejectFor} onOpenChange={(o) => !o && setRejectFor(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rejeter et libérer la réservation</DialogTitle>
            <DialogDescription>
              Aucun argent ne bouge. Le montant réservé redevient éligible pour le marchand.
            </DialogDescription>
          </DialogHeader>
          <Textarea value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Motif (obligatoire)" />
          <DialogFooter>
            <Button variant="destructive" onClick={submitReject} disabled={busy || reason.trim().length < 5}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Rejeter"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

export default function PayoutsAdmin() {
  const [bucket, setBucket] = useState<PayoutQueueBucket>("requested");
  const [scheduling, setScheduling] = useState(false);

  const runSchedule = async () => {
    setScheduling(true);
    const res = await generateSettlementSchedule();
    setScheduling(false);
    if (!res.ok) { toast.error(res.error); return; }
    toast.success(`File générée : ${JSON.stringify(res.result)}`);
  };

  return (
    <ModulePage module="payments" title="Règlements & versements">
      <Card className="p-4 mb-4 flex items-start gap-3">
        <ShieldAlert className="w-4 h-4 text-muted-foreground mt-0.5 shrink-0" />
        <p className="text-xs text-muted-foreground">
          Aucun bouton « marquer comme payé ». Un versement n'est réglé que lorsqu'une preuve
          de virement sortant exacte est enregistrée et réconciliée par le serveur. Le rail
          Orange Money sortant reste désactivé tant que l'étape 5 n'est pas activée.
        </p>
      </Card>

      <div className="flex justify-end mb-3">
        <Button variant="outline" size="sm" onClick={runSchedule} disabled={scheduling}>
          {scheduling ? <Loader2 className="w-4 h-4 animate-spin" /> : <CalendarClock className="w-4 h-4 mr-1" />}
          Générer la file programmée
        </Button>
      </div>

      <Tabs value={bucket} onValueChange={(v) => setBucket(v as PayoutQueueBucket)}>
        <TabsList className="flex-wrap h-auto">
          {BUCKETS.map((b) => <TabsTrigger key={b.key} value={b.key}>{b.label}</TabsTrigger>)}
        </TabsList>
        {BUCKETS.map((b) => (
          <TabsContent key={b.key} value={b.key} className="mt-4">
            {bucket === b.key && <QueueTable bucket={b.key} />}
          </TabsContent>
        ))}
      </Tabs>
    </ModulePage>
  );
}
