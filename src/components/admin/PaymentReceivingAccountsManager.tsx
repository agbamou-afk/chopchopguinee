import { useEffect, useState } from "react";
import { Loader2, Plus, Save, Wallet, AlertTriangle, Shuffle, Power } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import {
  ReceivingAccount,
  fetchReceivingAccounts,
  createReceivingAccount,
  updateReceivingAccountMetadata,
  setReceivingAccountActive,
  replaceReceivingAccountRouting,
} from "@/lib/admin/receivingAccounts";

export type { ReceivingAccount };

/**
 * G6 — every mutation goes through a governed server action. The browser holds
 * no write privilege on `payment_receiving_accounts`; routing changes are
 * four-eyes and never rewrite an account already used by financial history.
 */
export function PaymentReceivingAccountsManager({
  onChange,
}: {
  onChange?: (accounts: ReceivingAccount[]) => void;
}) {
  const [accounts, setAccounts] = useState<ReceivingAccount[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const [nLabel, setNLabel] = useState("");
  const [nPhone, setNPhone] = useState("");
  const [nInstr, setNInstr] = useState("");
  const [nNotes, setNNotes] = useState("");

  // Per-row draft state for governed actions.
  const [meta, setMeta] = useState<Record<string, { label: string; instructions: string; notes: string }>>({});
  const [routing, setRouting] = useState<Record<string, { phone: string; reason: string }>>({});
  const [activation, setActivation] = useState<Record<string, string>>({});

  const load = async () => {
    setLoading(true);
    const rows = await fetchReceivingAccounts();
    setAccounts(rows);
    setMeta(Object.fromEntries(rows.map((a) => [a.id, {
      label: a.label, instructions: a.public_instructions ?? "", notes: a.admin_notes ?? "",
    }])));
    setRouting(Object.fromEntries(rows.map((a) => [a.id, { phone: "", reason: "" }])));
    setActivation(Object.fromEntries(rows.map((a) => [a.id, ""])));
    onChange?.(rows);
    setLoading(false);
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const create = async () => {
    if (!nLabel.trim() || !nPhone.trim()) { toast.error("Libellé et numéro requis"); return; }
    setCreating(true);
    const res = await createReceivingAccount({
      label: nLabel.trim(), phone: nPhone.trim(),
      instructions: nInstr.trim() || null, notes: nNotes.trim() || null,
    });
    setCreating(false);
    if (!res.ok) { toast.error(res.error); return; }
    toast.success("Compte créé — inactif. Activez-le explicitement.");
    setNLabel(""); setNPhone(""); setNInstr(""); setNNotes("");
    void load();
  };

  const saveMeta = async (a: ReceivingAccount) => {
    const d = meta[a.id];
    setBusy(a.id);
    const res = await updateReceivingAccountMetadata({
      id: a.id, label: d.label, instructions: d.instructions || null, notes: d.notes || null,
    });
    setBusy(null);
    if (!res.ok) { toast.error(res.error); return; }
    toast.success("Informations enregistrées");
    void load();
  };

  const toggleActive = async (a: ReceivingAccount) => {
    const reason = (activation[a.id] ?? "").trim();
    if (!reason) { toast.error("Motif obligatoire pour activer ou désactiver"); return; }
    setBusy(a.id);
    const res = await setReceivingAccountActive(a.id, !a.is_active, reason);
    setBusy(null);
    if (!res.ok) { toast.error(res.error); return; }
    toast.success(a.is_active ? "Compte désactivé" : "Compte activé");
    void load();
  };

  const changeRouting = async (a: ReceivingAccount) => {
    const d = routing[a.id] ?? { phone: "", reason: "" };
    if (!d.phone.trim() || !d.reason.trim()) { toast.error("Nouveau numéro et motif requis"); return; }
    setBusy(a.id);
    const res = await replaceReceivingAccountRouting(a.id, d.phone.trim(), d.reason.trim());
    setBusy(null);
    if (!res.ok) { toast.error(res.error); return; }
    toast.success("Routage remplacé");
    void load();
  };

  const activeOM = accounts.filter((a) => a.provider === "orange_money" && a.is_active);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Wallet className="w-4 h-4 text-primary" />
        <p className="font-semibold text-sm">Numéros de réception Orange Money</p>
      </div>
      <p className="text-xs text-muted-foreground">
        Ces numéros sont affichés aux clients lorsqu'ils demandent une recharge ChopWallet.
        Chaque modification passe par une action contrôlée et tracée.
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
            <Input value={nPhone} onChange={(e) => setNPhone(e.target.value)} placeholder="+224XXXXXXXXX" />
          </div>
          <div className="md:col-span-2">
            <Label className="text-[11px]">Instructions publiques (optionnel)</Label>
            <Textarea rows={2} value={nInstr} onChange={(e) => setNInstr(e.target.value)}
              placeholder="Indiquez la référence dans le motif" />
          </div>
          <div className="md:col-span-2">
            <Label className="text-[11px]">Notes internes (non visibles client)</Label>
            <Input value={nNotes} onChange={(e) => setNNotes(e.target.value)} placeholder="Détenu par finance, etc." />
          </div>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Un nouveau compte est créé inactif. L'activation est un acte explicite et motivé.
        </p>
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
            {accounts.map((a) => {
              const d = meta[a.id] ?? { label: a.label, instructions: "", notes: "" };
              const r = routing[a.id] ?? { phone: "", reason: "" };
              const retired = a.retired_at !== null;
              return (
                <div key={a.id} className="p-4 space-y-3" data-testid="receiving-account-row">
                  <div className="flex items-center gap-2 flex-wrap">
                    <Badge variant="outline" className="text-[10px] uppercase">{a.provider}</Badge>
                    {retired ? (
                      <Badge variant="destructive" className="text-[10px]">Retiré</Badge>
                    ) : a.is_active ? (
                      <Badge className="text-[10px] bg-success/20 text-success border-success/30">Actif</Badge>
                    ) : (
                      <Badge variant="outline" className="text-[10px]">Inactif</Badge>
                    )}
                    <Badge variant="outline" className="text-[10px]">v{a.version}</Badge>
                    <span className="text-xs font-mono">{a.phone_e164}</span>
                  </div>

                  {retired ? (
                    <p className="text-xs text-muted-foreground">
                      Compte retiré le {new Date(a.retired_at as string).toLocaleString()} — conservé pour l'historique financier.
                    </p>
                  ) : (
                    <>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                        <div>
                          <Label className="text-[11px]">Libellé</Label>
                          <Input value={d.label}
                            onChange={(e) => setMeta((p) => ({ ...p, [a.id]: { ...d, label: e.target.value } }))} />
                        </div>
                        <div className="md:col-span-2">
                          <Label className="text-[11px]">Instructions publiques</Label>
                          <Textarea rows={2} value={d.instructions}
                            onChange={(e) => setMeta((p) => ({ ...p, [a.id]: { ...d, instructions: e.target.value } }))} />
                        </div>
                        <div className="md:col-span-2">
                          <Label className="text-[11px]">Notes internes</Label>
                          <Input value={d.notes}
                            onChange={(e) => setMeta((p) => ({ ...p, [a.id]: { ...d, notes: e.target.value } }))} />
                        </div>
                      </div>
                      <div className="flex justify-end">
                        <Button size="sm" onClick={() => saveMeta(a)} disabled={busy === a.id}>
                          <Save className="w-3.5 h-3.5 mr-1" /> Enregistrer les informations
                        </Button>
                      </div>

                      <div className="rounded-xl border p-3 space-y-2">
                        <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                          Activation
                        </p>
                        <Input placeholder="Motif obligatoire" value={activation[a.id] ?? ""}
                          onChange={(e) => setActivation((p) => ({ ...p, [a.id]: e.target.value }))} />
                        <div className="flex justify-end">
                          <Button size="sm" variant="outline" onClick={() => toggleActive(a)} disabled={busy === a.id}>
                            <Power className="w-3.5 h-3.5 mr-1" />
                            {a.is_active ? "Désactiver" : "Activer"}
                          </Button>
                        </div>
                      </div>

                      <div className="rounded-xl border border-destructive/30 p-3 space-y-2">
                        <p className="text-[11px] font-semibold uppercase tracking-wider text-destructive">
                          Changer le numéro de routage · quatre yeux
                        </p>
                        <p className="text-[11px] text-muted-foreground">
                          Si ce compte a déjà reçu des paiements, un compte successeur est créé et celui-ci est retiré :
                          l'historique financier n'est jamais réécrit.
                        </p>
                        <Input placeholder="+224XXXXXXXXX" value={r.phone}
                          onChange={(e) => setRouting((p) => ({ ...p, [a.id]: { ...r, phone: e.target.value } }))} />
                        <Input placeholder="Motif obligatoire" value={r.reason}
                          onChange={(e) => setRouting((p) => ({ ...p, [a.id]: { ...r, reason: e.target.value } }))} />
                        <div className="flex justify-end">
                          <Button size="sm" variant="destructive" onClick={() => changeRouting(a)} disabled={busy === a.id}>
                            <Shuffle className="w-3.5 h-3.5 mr-1" /> Remplacer le routage
                          </Button>
                        </div>
                      </div>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}
