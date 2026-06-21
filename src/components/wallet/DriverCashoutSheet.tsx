import { useEffect, useState, useCallback } from "react";
import { Loader2, ArrowDownToLine } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";
import { normalizeGuineaPhone, extractGuineaLocal, isValidGuineaLocal } from "@/lib/phone/guinea";

type Row = {
  id: string;
  amount_gnf: number;
  status: "pending" | "approved" | "paid" | "rejected" | "cancelled";
  payout_phone: string;
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

export function DriverCashoutSheet({
  available,
  onChanged,
  trigger,
}: {
  available: number;
  onChanged?: () => void;
  trigger: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState<string>("");
  const [phoneLocal, setPhoneLocal] = useState<string>("");
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase
      .from("driver_cashout_requests")
      .select("id, amount_gnf, status, payout_phone, provider_reference, rejected_reason, requested_at, paid_at")
      .order("requested_at", { ascending: false })
      .limit(20);
    setRows((data as Row[] | null) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    if (!open) return;
    refresh();
    // Prefill phone from profile
    (async () => {
      const { data: s } = await supabase.auth.getSession();
      const uid = s.session?.user.id;
      if (!uid) return;
      const { data: p } = await supabase
        .from("profiles")
        .select("phone")
        .eq("user_id", uid)
        .maybeSingle();
      const local = extractGuineaLocal(((p as { phone?: string } | null)?.phone) ?? "");
      if (local) setPhoneLocal(local);
    })();
  }, [open, refresh]);

  const amt = Number(amount);
  const amountValid = Number.isFinite(amt) && amt > 0 && amt % 5000 === 0 && amt <= available;
  const phoneValid = isValidGuineaLocal(phoneLocal);

  const submit = async () => {
    if (!amountValid) {
      toast.error("Montant invalide. Multiples de 5 000 GNF et ≤ solde disponible.");
      return;
    }
    if (!phoneValid) {
      toast.error("Numéro Orange Money invalide.");
      return;
    }
    setSubmitting(true);
    const { error } = await supabase.rpc("driver_cashout_create_request", {
      p_amount_gnf: amt,
      p_payout_phone: normalizeGuineaPhone(phoneLocal),
      p_driver_note: note.trim() || null,
    });
    setSubmitting(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Demande de retrait envoyée");
    setAmount("");
    setNote("");
    refresh();
    onChanged?.();
  };

  const cancel = async (id: string) => {
    const { error } = await supabase.rpc("driver_cashout_cancel_request", { p_id: id });
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Demande annulée");
    refresh();
    onChanged?.();
  };

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>{trigger}</SheetTrigger>
      <SheetContent side="bottom" className="max-h-[90vh] overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <ArrowDownToLine className="w-5 h-5" /> Demander un retrait
          </SheetTitle>
          <SheetDescription>
            Un administrateur enverra le paiement via Orange Money. Votre solde sera
            débité après confirmation du paiement.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 space-y-3">
          <div className="rounded-xl bg-muted/40 p-3 text-sm">
            Solde disponible : <span className="font-semibold">{formatGNF(available)}</span>
          </div>
          <div>
            <Label htmlFor="amt">Montant (multiples de 5 000 GNF)</Label>
            <Input
              id="amt"
              type="number"
              min={5000}
              step={5000}
              inputMode="numeric"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="50000"
            />
          </div>
          <div>
            <Label htmlFor="phone">Numéro Orange Money</Label>
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground px-2">+224</span>
              <Input
                id="phone"
                inputMode="tel"
                value={phoneLocal}
                onChange={(e) => setPhoneLocal(extractGuineaLocal(e.target.value))}
                placeholder="622 12 34 56"
              />
            </div>
          </div>
          <div>
            <Label htmlFor="note">Note (optionnel)</Label>
            <Textarea
              id="note"
              rows={2}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={300}
            />
          </div>
          <Button onClick={submit} disabled={submitting || !amountValid || !phoneValid} className="w-full">
            {submitting && <Loader2 className="w-4 h-4 animate-spin mr-2" />}
            Envoyer la demande
          </Button>
        </div>

        <div className="mt-6">
          <h3 className="text-sm font-semibold mb-2">Demandes récentes</h3>
          {loading ? (
            <div className="p-4 flex justify-center"><Loader2 className="w-4 h-4 animate-spin" /></div>
          ) : rows.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucune demande pour l'instant.</p>
          ) : (
            <ul className="space-y-2">
              {rows.map((r) => {
                const s = STATUS_LABEL[r.status];
                return (
                  <li key={r.id} className="rounded-xl border border-border p-3 text-sm">
                    <div className="flex items-center justify-between">
                      <div className="font-medium">{formatGNF(r.amount_gnf)}</div>
                      <span className={`text-[11px] px-2 py-0.5 rounded-full ${s.tone}`}>{s.label}</span>
                    </div>
                    <div className="text-xs text-muted-foreground mt-1">
                      {new Date(r.requested_at).toLocaleString()} · {r.payout_phone}
                    </div>
                    {r.provider_reference && (
                      <div className="text-xs text-muted-foreground mt-0.5">Réf. OM : {r.provider_reference}</div>
                    )}
                    {r.rejected_reason && (
                      <div className="text-xs text-destructive mt-0.5">Motif : {r.rejected_reason}</div>
                    )}
                    {r.status === "pending" && (
                      <button
                        onClick={() => cancel(r.id)}
                        className="mt-2 text-xs text-muted-foreground underline"
                      >
                        Annuler la demande
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}