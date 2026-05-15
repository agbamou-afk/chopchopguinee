import { useEffect, useState } from "react";
import { formatGNF } from "@/lib/format";
import { QRCodeSVG } from "qrcode.react";
import { Loader2, ShieldCheck, X } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

interface MyQrModalProps {
  open: boolean;
  onClose: () => void;
  userId: string;
  phone: string | null;
}

type PendingTopup = {
  id: string;
  reference: string;
  amount_gnf: number;
  confirmation_code: string;
  expires_at: string;
};

export function MyQrModal({ open, onClose, userId, phone }: MyQrModalProps) {
  const [pending, setPending] = useState<PendingTopup | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open) {
      // Avoid flashing a stale confirmation code the next time the modal opens.
      setPending(null);
      return;
    }
    let active = true;
    // Reset before fetching so a previous session's code never lingers visibly.
    setPending(null);

    const fetchPending = async () => {
      setLoading(true);
      const { data } = await supabase
        .from("topup_requests")
        .select("id, reference, amount_gnf, confirmation_code, expires_at")
        .eq("client_user_id", userId)
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (active) {
        setPending(data as PendingTopup | null);
        setLoading(false);
      }
    };
    fetchPending();

    const channel = supabase
      .channel(`topup-${userId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "topup_requests",
          filter: `client_user_id=eq.${userId}`,
        },
        () => fetchPending(),
      )
      .subscribe();

    return () => {
      active = false;
      supabase.removeChannel(channel);
    };
  }, [open, userId]);

  const cancelPending = async () => {
    if (!pending) return;
    const { error } = await supabase.rpc("wallet_topup_cancel", {
      p_topup_id: pending.id,
      p_reason: "Cancelled by user",
    });
    if (error) toast.error(error.message);
    else {
      toast.success("Recharge annulée");
      setPending(null);
    }
  };

  const qrPayload = JSON.stringify({ t: "chopchop-user", id: userId });

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-4"
          onClick={onClose}
        >
          <motion.div
            initial={{ y: 40, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 40, opacity: 0 }}
            onClick={(e) => e.stopPropagation()}
            className="bg-card w-full max-w-sm rounded-3xl shadow-elevated p-6 relative overflow-hidden"
          >
            <div className="pointer-events-none absolute inset-x-10 top-0 h-px saffron-seam" aria-hidden />
            <div className="flex items-center justify-between mb-4">
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground leading-none">CHOPWallet</p>
                <h2 className="text-lg font-bold text-foreground leading-tight mt-0.5">Mon QR CHOP CHOP</h2>
              </div>
              <button onClick={onClose} className="p-1 hover:bg-muted rounded-lg">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="surface-money p-4 rounded-2xl mb-4 flex justify-center">
              <div className="bg-white p-3 rounded-xl ring-1 ring-border/50">
                <QRCodeSVG value={qrPayload} size={200} level="M" includeMargin={false} />
              </div>
            </div>

            <div className="text-center mb-4">
              <p className="text-xs text-muted-foreground">Présentez ce code à l'agent</p>
              {phone && (
                <p className="text-sm font-medium text-foreground mt-1">{phone}</p>
              )}
            </div>

            {loading ? (
              <div className="flex justify-center py-3">
                <Loader2 className="w-5 h-5 animate-spin text-muted-foreground" />
              </div>
            ) : pending ? (
              <motion.div
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                className="surface-money rounded-2xl p-4"
              >
                <div className="flex items-center gap-2 mb-2">
                  <ShieldCheck className="w-4 h-4 text-primary" />
                  <p className="text-xs font-semibold text-primary uppercase tracking-wide">
                    Code de confirmation
                  </p>
                </div>
                <p className="text-3xl font-bold text-foreground tracking-[0.3em] text-center my-2">
                  {pending.confirmation_code}
                </p>
                <p className="text-xs text-muted-foreground text-center mb-3">
                  Recharge de{" "}
                  <span className="font-semibold text-foreground">
                    {formatGNF(pending.amount_gnf)}
                  </span>
                  . Donnez ce code à l'agent <strong>uniquement après</strong> avoir remis
                  l'argent.
                </p>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={cancelPending}
                  className="w-full"
                >
                  Annuler la recharge
                </Button>
              </motion.div>
            ) : (
              <p className="text-xs text-muted-foreground text-center">
                Aucune recharge en attente. L'agent va scanner votre QR ou saisir votre
                numéro.
              </p>
            )}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}