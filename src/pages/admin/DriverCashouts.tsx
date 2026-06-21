import { useEffect, useState, useCallback } from "react";
import { Loader2, Check, X } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { ModulePage } from "@/components/admin/ModulePage";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter,
  DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";

type Row = {
  id: string;
  driver_user_id: string;
  amount_gnf: number;
  status: "pending" | "approved" | "paid" | "rejected" | "cancelled";
  payout_method: string;
  payout_phone: string;
  driver_note: string | null;
  admin_note: string | null;
  provider_reference: string | null;
  rejected_reason: string | null;
  requested_at: string;
  paid_at: string | null;
};

const STATUS_LABEL: Record<Row["status"], { label: string; tone: string }> = {
  pending:   { label: "En attente", tone: "bg-warning/15 text-warning" },
  approved:  { label: "Approuvé",   tone: "bg-secondary/30 text-foreground" },
  paid:      { label: "Payé",       tone: "bg-success/15 text-success" },
  rejected:  { label: "Rejeté",     tone: "bg-destructive/15 text-destructive" },
  cancelled: { label: "Annulé",     tone: "bg-muted text-muted-foreground" },
};

export default function DriverCashouts() {
  const [rows, setRows] = useState<Row[]>([]);
  const [profiles, setProfiles] = useState<Record<string, { full_name: string | null; phone: string | null }>>({});
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<"all" | Row["status"]>("pending");

  const [payOpen, setPayOpen] = useState(false);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [target, setTarget] = useState<Row | null>(null);
  const [providerRef, setProviderRef] = useState("");
  const [adminNote, setAdminNote] = useState("");
  const [rejectReason, setRejectReason] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    let q = supabase
      .from("driver_cashout_requests")
      .select("*")
      .order("requested_at", { ascending: false })
      .limit(200);
    if (statusFilter !== "all") q = q.eq("status", statusFilter);
    const { data } = await q;
    const list = (data as Row[] | null) ?? [];
    setRows(list);

    const ids = Array.from(new Set(list.map((r) => r.driver_user_id)));
    if (ids.length) {
      const { data: profs } = await supabase
        .from("profiles")
        .select("user_id, full_name, phone")
        .in("user_id", ids);
      const map: typeof profiles = {};
      ((profs as { user_id: string; full_name: string | null; phone: string | null }[] | null) ?? []).forEach((p) => {
        map[p.user_id] = { full_name: p.full_name, phone: p.phone };
      });
      setProfiles(map);
    }
    setLoading(false);
  }, [statusFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  const openPay = (r: Row) => {
    setTarget(r);
    setProviderRef("");
    setAdminNote("");
    setPayOpen(true);
  };
  const openReject = (r: Row) => {
    setTarget(r);
    setRejectReason("");
    setRejectOpen(true);
  };

  const submitPay = async () => {
    if (!target || !providerRef.trim()) {
      toast.error("Référence Orange Money requise");
      return;
    }
    setSubmitting(true);
    const { error } = await supabase.rpc("driver_cashout_mark_paid", {
      p_id: target.id,
      p_provider_reference: providerRef.trim(),
      p_admin_note: adminNote.trim() || null,
    });
    setSubmitting(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Versement enregistré");
    setPayOpen(false);
    refresh();
  };

  const submitReject = async () => {
    if (!target || !rejectReason.trim()) {
      toast.error("Motif requis");
      return;
    }
    setSubmitting(true);
    const { error } = await supabase.rpc("driver_cashout_reject_request", {
      p_id: target.id,
      p_reason: rejectReason.trim(),
    });
    setSubmitting(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Demande rejetée");
    setRejectOpen(false);
    refresh();
  };

  return (
    <ModulePage
      module="wallet"
      title="Retraits chauffeurs"
      subtitle="Demandes de versement Orange Money — réservé finance_admin / god_admin"
      actions={
        <div className="flex gap-1">
          {(["pending","paid","rejected","cancelled","all"] as const).map((s) => (
            <Button
              key={s}
              size="sm"
              variant={statusFilter === s ? "default" : "outline"}
              onClick={() => setStatusFilter(s)}
            >
              {s === "all" ? "Tous" : STATUS_LABEL[s as Row["status"]]?.label ?? s}
            </Button>
          ))}
        </div>
      }
    >
      <Card className="p-0 overflow-hidden">
        {loading ? (
          <div className="p-8 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50">
                <tr className="text-left">
                  <th className="p-3">Demande</th>
                  <th className="p-3">Chauffeur</th>
                  <th className="p-3 text-right">Montant</th>
                  <th className="p-3">OM</th>
                  <th className="p-3">Statut</th>
                  <th className="p-3">Référence</th>
                  <th className="p-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const p = profiles[r.driver_user_id];
                  const s = STATUS_LABEL[r.status];
                  return (
                    <tr key={r.id} className="border-t align-top">
                      <td className="p-3 text-xs">{new Date(r.requested_at).toLocaleString()}</td>
                      <td className="p-3">
                        <div className="font-medium">{p?.full_name ?? "—"}</div>
                        <div className="text-xs text-muted-foreground">{p?.phone ?? r.driver_user_id.slice(0, 8)}</div>
                      </td>
                      <td className="p-3 text-right font-semibold">{formatGNF(r.amount_gnf)}</td>
                      <td className="p-3 text-xs">{r.payout_phone}</td>
                      <td className="p-3"><span className={`text-[11px] px-2 py-0.5 rounded-full ${s.tone}`}>{s.label}</span></td>
                      <td className="p-3 text-xs text-muted-foreground">
                        {r.provider_reference ?? (r.rejected_reason ? <span className="text-destructive">{r.rejected_reason}</span> : "—")}
                      </td>
                      <td className="p-3 text-right">
                        {(r.status === "pending" || r.status === "approved") && (
                          <div className="flex gap-2 justify-end">
                            <Button size="sm" onClick={() => openPay(r)}><Check className="w-3 h-3 mr-1" />Payé</Button>
                            <Button size="sm" variant="outline" onClick={() => openReject(r)}><X className="w-3 h-3 mr-1" />Rejeter</Button>
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
                {rows.length === 0 && (
                  <tr><td colSpan={7} className="p-8 text-center text-muted-foreground">Aucune demande.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Dialog open={payOpen} onOpenChange={setPayOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Marquer comme payé</DialogTitle>
            <DialogDescription>
              Confirmez que le versement Orange Money a été envoyé manuellement.
              Le wallet chauffeur sera débité de {target && formatGNF(target.amount_gnf)}.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label htmlFor="ref">Référence transaction OM</Label>
              <Input id="ref" value={providerRef} onChange={(e) => setProviderRef(e.target.value)} placeholder="ex: OM-2026XXXX" />
            </div>
            <div>
              <Label htmlFor="note">Note (optionnel)</Label>
              <Textarea id="note" rows={2} value={adminNote} onChange={(e) => setAdminNote(e.target.value)} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPayOpen(false)} disabled={submitting}>Annuler</Button>
            <Button onClick={submitPay} disabled={submitting || !providerRef.trim()}>
              {submitting && <Loader2 className="w-4 h-4 animate-spin mr-2" />}
              Confirmer
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={rejectOpen} onOpenChange={setRejectOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rejeter la demande</DialogTitle>
            <DialogDescription>Le wallet chauffeur ne sera pas débité.</DialogDescription>
          </DialogHeader>
          <div>
            <Label htmlFor="reason">Motif</Label>
            <Textarea id="reason" rows={3} value={rejectReason} onChange={(e) => setRejectReason(e.target.value)} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectOpen(false)} disabled={submitting}>Annuler</Button>
            <Button variant="destructive" onClick={submitReject} disabled={submitting || !rejectReason.trim()}>
              {submitting && <Loader2 className="w-4 h-4 animate-spin mr-2" />}
              Rejeter
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </ModulePage>
  );
}