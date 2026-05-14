import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { CheckCircle2, Star, Loader2, Wallet, Banknote, Percent, TrendingUp, Power } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { formatGNF } from "@/lib/format";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { useDriverSession } from "@/contexts/DriverSessionContext";
import { useDriverEarnings } from "@/hooks/useDriverEarnings";

interface Props {
  rideId: string;
  fareGnf: number;
  commissionBps?: number;
  clientName?: string | null;
  paymentLabel?: string;
  onClose: () => void;
}

/**
 * Post-trip earnings receipt for the driver:
 * - Fare / commission / net earning breakdown
 * - Star rating for the client (records via ride_rate RPC)
 * - Single "Terminer" exit
 */
export function DriverTripReceipt({
  rideId, fareGnf, commissionBps = 1500, clientName, paymentLabel = "Espèces", onClose,
}: Props) {
  const commission = Math.round((fareGnf * commissionBps) / 10_000);
  const earning = Math.max(0, fareGnf - commission);
  const [score, setScore] = useState<number>(5);
  const [comment, setComment] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [resuming, setResuming] = useState(false);
  const { isOnline, togglePresence } = useDriverSession();
  const { todayGnf, completedToday, refetch: refetchEarnings } = useDriverEarnings();

  // Refresh daily earnings as soon as the receipt mounts so the new ride
  // is reflected in the "today" total.
  useEffect(() => {
    refetchEarnings().catch(() => {});
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
    try { Analytics.track("driver.ride.completed" as any, { metadata: { rideId, rated: score } }); } catch {}
    toast({ title: "Merci !", description: "Votre note a été enregistrée." });
  };

  const goBackOnline = async () => {
    setResuming(true);
    try {
      if (!isOnline) await togglePresence();
      try { Analytics.track("driver.online" as any, { metadata: { from: "post_trip_receipt" } }); } catch {}
    } finally {
      setResuming(false);
      onClose();
    }
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
        <p className="text-sm opacity-90">Course terminée</p>
        <motion.p
          key={earning}
          initial={{ y: 8, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-3xl font-bold tabular-nums mt-1"
        >
          +{formatGNF(earning)}
        </motion.p>
        <p className="text-xs opacity-80 mt-1">Net encaissé · {paymentLabel}</p>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <motion.section
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15 }}
          className="rounded-xl border border-primary/20 bg-primary/5 p-4"
        >
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="text-[11px] uppercase tracking-wider text-muted-foreground">
                Vos gains aujourd'hui
              </p>
              <p className="text-2xl font-bold tabular-nums text-primary">
                {formatGNF(todayGnf)}
              </p>
              <p className="text-xs text-muted-foreground">
                {completedToday} course{completedToday > 1 ? "s" : ""} · mise à jour
              </p>
            </div>
            <div className="rounded-full bg-primary/10 p-3">
              <TrendingUp className="w-6 h-6 text-primary" />
            </div>
          </div>
        </motion.section>

        <section className="rounded-xl border border-border bg-card p-4 space-y-2">
          <h3 className="text-sm font-semibold mb-1">Détails</h3>
          <Row icon={Banknote} label="Tarif client" value={formatGNF(fareGnf)} />
          <Row icon={Percent} label={`Commission (${(commissionBps / 100).toFixed(0)}%)`}
            value={`-${formatGNF(commission)}`} muted />
          <div className="border-t border-border pt-2 mt-1">
            <Row icon={Wallet} label="Vos gains" value={formatGNF(earning)} bold />
          </div>
        </section>

        <section className="rounded-xl border border-border bg-card p-4 space-y-3">
          <div>
            <h3 className="text-sm font-semibold">Notez le client{clientName ? ` (${clientName})` : ""}</h3>
            <p className="text-xs text-muted-foreground">Aide la communauté CHOP CHOP à rester respectueuse.</p>
          </div>
          <div className="flex justify-center gap-1">
            {[1, 2, 3, 4, 5].map((i) => (
              <button key={i} type="button" onClick={() => setScore(i)} aria-label={`${i} étoiles`}
                className="p-1 rounded-md hover:bg-muted transition disabled:opacity-60"
                disabled={submitted}>
                <Star className={`w-9 h-9 ${i <= score ? "fill-secondary text-secondary" : "text-muted-foreground/40"}`} />
              </button>
            ))}
          </div>
          <Textarea
            placeholder="Commentaire (optionnel)" value={comment} disabled={submitted}
            onChange={(e) => setComment(e.target.value.slice(0, 280))}
            className="min-h-[72px]"
          />
          {!submitted && (
            <Button onClick={submit} disabled={submitting} className="w-full h-11" variant="outline">
              {submitting ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Star className="w-4 h-4 mr-2" />}
              Envoyer la note
            </Button>
          )}
        </section>
      </div>

      <div className="p-4 border-t border-border bg-card shrink-0 space-y-2">
        <Button
          onClick={goBackOnline}
          disabled={resuming}
          className="w-full h-12 gradient-primary font-semibold gap-2"
        >
          {resuming ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            <Power className="w-4 h-4" />
          )}
          {isOnline ? "Continuer en ligne" : "Retour en ligne"}
        </Button>
        <Button onClick={onClose} variant="ghost" className="w-full h-10 text-muted-foreground">
          Fermer
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