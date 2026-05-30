import { useEffect, useState } from "react";
import { Loader2, Plus, Save, Wallet, AlertTriangle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";

export type ReceivingAccount = {
  id: string;
  provider: string;
  label: string;
  phone_e164: string;
  is_active: boolean;
  public_instructions: string | null;
  admin_notes: string | null;
  created_at: string;
  updated_at: string;
};

export function PaymentReceivingAccountsManager({
  onChange,
}: {
  onChange?: (accounts: ReceivingAccount[]) => void;
}) {
  const [accounts, setAccounts] = useState<ReceivingAccount[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const [nLabel, setNLabel] = useState("");
  const [nPhone, setNPhone] = useState("");
  const [nInstr, setNInstr] = useState("");
  const [nNotes, setNNotes] = useState("");

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("payment_receiving_accounts")
      .select("*")
      .order("provider", { ascending: true })
      .order("updated_at", { ascending: false });
    if (error) toast.error(error.message);
    const rows = (data ?? []) as ReceivingAccount[];
    setAccounts(rows);
    onChange?.(rows);
    setLoading(false);
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const create = async () => {
    if (!nLabel.trim() || !nPhone.trim()) {
      toast.error("Libellé et numéro requis");
      return;
    }
    setCreating(true);
    const { error } = await supabase.from("payment_receiving_accounts").insert({
      provider: "orange_money",
      label: nLabel.trim(),
      phone_e164: nPhone.trim(),
      public_instructions: nInstr.trim() || null,
      admin_notes: nNotes.trim() || null,
      is_active: true,
    });
    setCreating(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Numéro de réception ajouté");
    setNLabel(""); setNPhone(""); setNInstr(""); setNNotes("");
    void load();
  };

  const save = async (a: ReceivingAccount) => {
    setSaving(a.id);
    const { error } = await supabase
      .from("payment_receiving_accounts")
      .update({
        label: a.label,
        phone_e164: a.phone_e164,
        public_instructions: a.public_instructions,
        admin_notes: a.admin_notes,
        is_active: a.is_active,
      })
      .eq("id", a.id);
    setSaving(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Enregistré");
    void load();
  };

  const patch = (id: string, p: Partial<ReceivingAccount>) =>
    setAccounts((prev) => prev.map((x) => (x.id === id ? { ...x, ...p } : x)));

  const activeOM = accounts.filter((a) => a.provider === "orange_money" && a.is_active);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Wallet className="w-4 h-4 text-primary" />
        <p className="font-semibold text-sm">Numéros de réception Orange Money</p>
      </div>
      <p className="text-xs text-muted-foreground">
        Ces numéros sont affichés aux clients lorsqu'ils demandent une recharge ChopWallet.
      </p>

      {!loading && activeOM.length === 0 && (
        <div className="rounded-2xl bg-destructive/10 border border-destructive/30 p-3 flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 text-destructive shrink-0 mt-0.5" />
          <p className="text-xs text-foreground">
            Aucun numéro de réception Orange Money actif. La recharge OM est désactivée côté client.
          </p>
        </div>
      )}

      <Card className="p-4 space-y-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Ajouter un numéro
        </p>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
          <div>
            <Label className="text-[11px]">Libellé</Label>
            <Input value={nLabel} onChange={(e) => setNLabel(e.target.value)} placeholder="Compte OM principal" />
          </div>
          <div>
            <Label className="text-[11px]">Numéro OM (+224…)</Label>
            <Input value={nPhone} onChange={(e) => setNPhone(e.target.value)} placeholder="+224 6XX XX XX XX" />
          </div>
          <div className="md:col-span-2">
            <Label className="text-[11px]">Instructions publiques (optionnel)</Label>
            <Textarea
              rows={2}
              value={nInstr}
              onChange={(e) => setNInstr(e.target.value)}
              placeholder="Indiquez la référence dans le motif"
            />
          </div>
          <div className="md:col-span-2">
            <Label className="text-[11px]">Notes internes (non visibles client)</Label>
            <Input value={nNotes} onChange={(e) => setNNotes(e.target.value)} placeholder="Détenu par finance, etc." />
          </div>
        </div>
        <div className="flex justify-end">
          <Button onClick={create} disabled={creating || !nLabel.trim() || !nPhone.trim()}>
            {creating ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Plus className="w-4 h-4 mr-2" />}
            Ajouter
          </Button>
        </div>
      </Card>

      <Card className="p-0 overflow-hidden">
        {loading ? (
          <div className="p-12 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
        ) : accounts.length === 0 ? (
          <div className="p-12 text-center text-muted-foreground text-sm">Aucun numéro configuré.</div>
        ) : (
          <div className="divide-y">
            {accounts.map((a) => (
              <div key={a.id} className="p-4 space-y-2">
                <div className="flex items-center gap-2">
                  <Badge variant="outline" className="text-[10px] uppercase">{a.provider}</Badge>
                  {a.is_active ? (
                    <Badge className="text-[10px] bg-success/20 text-success border-success/30">Actif</Badge>
                  ) : (
                    <Badge variant="outline" className="text-[10px]">Inactif</Badge>
                  )}
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                  <div>
                    <Label className="text-[11px]">Libellé</Label>
                    <Input value={a.label} onChange={(e) => patch(a.id, { label: e.target.value })} />
                  </div>
                  <div>
                    <Label className="text-[11px]">Numéro OM</Label>
                    <Input value={a.phone_e164} onChange={(e) => patch(a.id, { phone_e164: e.target.value })} />
                  </div>
                  <div className="md:col-span-2">
                    <Label className="text-[11px]">Instructions publiques</Label>
                    <Textarea
                      rows={2}
                      value={a.public_instructions ?? ""}
                      onChange={(e) => patch(a.id, { public_instructions: e.target.value })}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <Label className="text-[11px]">Notes internes</Label>
                    <Input
                      value={a.admin_notes ?? ""}
                      onChange={(e) => patch(a.id, { admin_notes: e.target.value })}
                    />
                  </div>
                </div>
                <div className="flex items-center justify-between pt-1">
                  <label className="flex items-center gap-2 text-xs">
                    <Switch
                      checked={a.is_active}
                      onCheckedChange={(v) => patch(a.id, { is_active: v })}
                    />
                    Actif
                  </label>
                  <Button size="sm" onClick={() => save(a)} disabled={saving === a.id}>
                    {saving === a.id ? <Loader2 className="w-3.5 h-3.5 animate-spin mr-1" /> : <Save className="w-3.5 h-3.5 mr-1" />}
                    Enregistrer
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}