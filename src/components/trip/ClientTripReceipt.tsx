import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { CheckCircle2, Star, Loader2, Wallet, Banknote, Receipt, Heart, User, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { formatGNF } from "@/lib/format";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { SecuredByChopPay } from "@/components/trust/TrustCues";

interface Props {
  rideId: string;
  fareGnf: number;
  driverName?: string | null;
  paymentLabel?: string;
  onClose: () => void;
}

/**
 * Post-trip receipt for the client (mirror of DriverTripReceipt):
 * - Fare summary
 * - 1–5 star rating for the driver via ride_rate RPC
 * - "Terminer" exit
 */
export function ClientTripReceipt({
  rideId, fareGnf, driverName, paymentLabel = "Espèces", onClose,
}: Props) {
  const [score, setScore] = useState<number>(5);
  const [comment, setComment] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  useEffect(() => {
    try {
      Analytics.track("receipt.viewed" as any, {
        metadata: { role: "client", rideId, payment: paymentLabel },
      });
    } catch {}
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const submit = async () => {
    setSubmitting(true);
    const { error } = await supabase.rpc("ride_rate", {
      p_ride_id: rideId, p_score: score, p_comment: comment || null,
    });
    setSubmitting(false);
    if (error) { toast({ title: "Note non enregistrée", description: error.message }); return; }
    setSubmitted(true);
    try { Analytics.track("client.ride.completed", { metadata: { rideId, rated: score } }); } catch {}
    toast({ title: "Merci !", description: "Votre note a été enregistrée." });
  };

  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      <div className="gradient-primary px-4 py-6 text-primary-foreground text-center shrink-0">
        <motion.div
          initial={{ scale: 0.6, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: "spring", stiffness: 320, damping: 18 }}
        >
          <CheckCircle2 className="w-12 h-12 mx-auto mb-2" />
        </motion.div>
        <p className="text-sm opacity-90">Merci d'avoir voyagé avec CHOP CHOP</p>
        <motion.p
          key={fareGnf}
          initial={{ y: 8, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-3xl font-bold tabular-nums mt-1"
        >
          {formatGNF(fareGnf)}
        </motion.p>
        <p className="text-xs opacity-80 mt-1">Total payé · {paymentLabel}</p>
        <p className="text-[11px] opacity-90 mt-1 inline-flex items-center gap-1 justify-center">
          <ShieldCheck className="w-3 h-3" /> Paiement confirmé · CHOPPay
        </p>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {driverName && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.12 }}
            className="flex items-center gap-3 rounded-xl border border-border bg-card p-3"
          >
            <div className="rounded-full bg-primary/10 p-2">
              <User className="w-5 h-5 text-primary" />
            </div>
            <div className="min-w-0">
              <p className="text-[11px] uppercase tracking-wider text-muted-foreground">
                Votre chauffeur
              </p>
              <p className="text-sm font-semibold truncate">{driverName}</p>
            </div>
          </motion.div>
        )}

        <section className="rounded-xl border border-border bg-card p-4 space-y-2">
          <h3 className="text-sm font-semibold mb-1">Reçu</h3>
          <Row icon={Banknote} label="Tarif de la course" value={formatGNF(fareGnf)} />
          <Row icon={Receipt} label="Mode de paiement" value={paymentLabel} muted />
          <div className="border-t border-border pt-2 mt-1">
            <Row icon={Wallet} label="Total" value={formatGNF(fareGnf)} bold />
          </div>
          <SecuredByChopPay className="pt-1" />
        </section>

        <section className="rounded-xl border border-border bg-card p-4 space-y-3">
          <AnimatePresence mode="wait">
            {submitted ? (
              <motion.div
                key="thanks"
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0 }}
                className="flex flex-col items-center text-center py-3 gap-2"
              >
                <motion.div
                  initial={{ scale: 0.4 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", stiffness: 360, damping: 16 }}
                  className="rounded-full bg-primary/10 p-3"
                >
                  <Heart className="w-6 h-6 text-primary fill-primary" />
                </motion.div>
                <p className="text-sm font-semibold">Merci pour votre avis !</p>
                <p className="text-xs text-muted-foreground">
                  Votre note aide la communauté CHOP CHOP à grandir.
                </p>
              </motion.div>
            ) : (
              <motion.div
                key="rate"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="space-y-3"
              >
                <div>
                  <h3 className="text-sm font-semibold">
                    Notez votre chauffeur{driverName ? ` (${driverName})` : ""}
                  </h3>
                  <p className="text-xs text-muted-foreground">Votre avis aide la communauté CHOP CHOP.</p>
                </div>
                <div className="flex justify-center gap-1">
                  {[1, 2, 3, 4, 5].map((i) => (
                    <button key={i} type="button" onClick={() => setScore(i)} aria-label={`${i} étoiles`}
                      className="p-1 rounded-md hover:bg-muted transition">
                      <Star className={`w-9 h-9 transition ${i <= score ? "fill-secondary text-secondary" : "text-muted-foreground/40"}`} />
                    </button>
                  ))}
                </div>
                <Textarea
                  placeholder="Commentaire (optionnel)" value={comment}
                  onChange={(e) => setComment(e.target.value.slice(0, 280))}
                  className="min-h-[72px]"
                />
                <Button onClick={submit} disabled={submitting} className="w-full h-11" variant="outline">
                  {submitting ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Star className="w-4 h-4 mr-2" />}
                  Envoyer la note
                </Button>
              </motion.div>
            )}
          </AnimatePresence>
        </section>
      </div>

      <div className="p-4 border-t border-border bg-card shrink-0">
        <Button onClick={onClose} className="w-full h-12 gradient-primary font-semibold">
          Terminer
        </Button>
      </div>
    </motion.div>
  );
}

function Row({ icon: Icon, label, value, muted, bold }: {
  icon: React.ComponentType<{ className?: string }>; label: string; value: string;
  muted?: boolean; bold?: boolean;
}) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className={`inline-flex items-center gap-2 ${muted ? "text-muted-foreground" : ""}`}>
        <Icon className="w-4 h-4" /> {label}
      </span>
      <span className={`tabular-nums ${bold ? "font-bold text-base" : ""}`}>{value}</span>
    </div>
  );
}