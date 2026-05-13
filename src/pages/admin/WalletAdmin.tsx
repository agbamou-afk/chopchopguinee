import { useEffect, useState } from "react";
import { Loader2, Plus } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { ModulePage } from "@/components/admin/ModulePage";
import { formatGNF } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { toast } from "sonner";

export default function WalletAdmin() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [canCredit, setCanCredit] = useState(false);
  const [open, setOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState({ user_id: "", amount: "", reason: "", provider_tx_id: "" });

  const refresh = async () => {
    setLoading(true);
    const { data } = await supabase
      .from("wallet_transactions")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(100);
    setRows(data ?? []);
    setLoading(false);
  };

  useEffect(() => {
    refresh();
    (async () => {
      const { data: s } = await supabase.auth.getSession();
      const uid = s.session?.user.id;
      if (!uid) return;
      const { data: roles } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", uid);
      const list = (roles ?? []).map((r: any) => r.role);
      setCanCredit(list.includes("god_admin") || list.includes("finance_admin"));
    })();
  }, []);

  const submitCredit = async () => {
    const amt = Number(form.amount);
    if (!form.user_id || !amt || amt <= 0 || !form.reason.trim()) {
      toast.error("Renseignez user_id, montant > 0 et raison");
      return;
    }
    if (!navigator.onLine) {
      toast.error("Connexion indisponible. Crédit admin bloqué hors ligne.");
      return;
    }
    setSubmitting(true);
    const { error } = await supabase.rpc("wallet_admin_credit", {
      p_user_id: form.user_id.trim(),
      p_amount_gnf: amt,
      p_reason: form.reason.trim(),
      p_provider_tx_id: form.provider_tx_id.trim() || null,
    });
    setSubmitting(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Wallet crédité");
    setOpen(false);
    setForm({ user_id: "", amount: "", reason: "", provider_tx_id: "" });
    refresh();
  };

  return (
    <ModulePage
      module="wallet"
      title="Wallet / Ledger"
      subtitle="Journal de toutes les transactions wallet (100 dernières)"
      actions={
        canCredit ? (
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="gap-1"><Plus className="w-4 h-4" /> Créditer un wallet</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Crédit manuel</DialogTitle>
                <DialogDescription>
                  Réservé aux finance_admin / god_admin. Toute action est journalisée.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3">
                <div>
                  <Label htmlFor="uid">User ID (UUID)</Label>
                  <Input id="uid" value={form.user_id} onChange={(e) => setForm({ ...form, user_id: e.target.value })} placeholder="00000000-..." />
                </div>
                <div>
                  <Label htmlFor="amt">Montant (GNF)</Label>
                  <Input id="amt" type="number" min={1} value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} />
                </div>
                <div>
                  <Label htmlFor="reason">Raison</Label>
                  <Textarea id="reason" rows={3} value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} placeholder="Ex: Compensation incident OM #1234" />
                </div>
                <div>
                  <Label htmlFor="ptx">Provider transaction ID (optionnel)</Label>
                  <Input id="ptx" value={form.provider_tx_id} onChange={(e) => setForm({ ...form, provider_tx_id: e.target.value })} />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>Annuler</Button>
                <Button onClick={submitCredit} disabled={submitting}>
                  {submitting && <Loader2 className="w-4 h-4 animate-spin mr-2" />}
                  Créditer
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        ) : null
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
                  <th className="p-3">Date</th><th className="p-3">Type</th><th className="p-3">Statut</th>
                  <th className="p-3 text-right">Montant</th><th className="p-3">Référence</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className="border-t">
                    <td className="p-3 text-xs">{new Date(r.created_at).toLocaleString()}</td>
                    <td className="p-3">{r.type}</td>
                    <td className="p-3"><span className="text-xs px-2 py-0.5 rounded-full bg-muted">{r.status}</span></td>
                    <td className="p-3 text-right font-medium">{formatGNF(r.amount_gnf)}</td>
                    <td className="p-3 text-xs text-muted-foreground">{r.reference}</td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-muted-foreground">Aucune transaction.</td></tr>}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </ModulePage>
  );
}