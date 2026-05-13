import { useState } from "react";
import { motion } from "framer-motion";
import { CheckCircle2, Star, Loader2, Wallet, Banknote, Percent } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { formatGNF } from "@/lib/format";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { Analytics } from "@/lib/analytics/AnalyticsService";

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

  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      <div className="gradient-primary px-4 py-6 text-primary-foreground text-center shrink-0">
        <CheckCircle2 className="w-12 h-12 mx-auto mb-2 opacity-90" />
        <p className="text-sm opacity-90">Course terminée</p>
        <p className="text-3xl font-bold tabular-nums mt-1">{formatGNF(earning)}</p>
        <p className="text-xs opacity-80 mt-1">Net encaissé · {paymentLabel}</p>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
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