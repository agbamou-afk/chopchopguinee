import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { listCustomerMissions } from "@/lib/missions/missions";
import { customerConfirmDelivery } from "@/lib/missions/proof";
import { isTerminalState, MISSION_STATE_LABEL, type Mission } from "@/lib/missions/types";
import { Button } from "@/components/ui/button";
import { Loader2, ShieldCheck, KeyRound, Check } from "lucide-react";
import { toast } from "sonner";

/**
 * Phase 5 — buyer surface for marketplace_delivery missions.
 * Shows the 6-digit handoff code the buyer must give the courier and
 * a "Confirmer la réception" button once the courier marks delivered.
 */
export function CustomerMarketplaceDeliveries({ userId }: { userId: string | null }) {
  const [missions, setMissions] = useState<Mission[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const reload = useCallback(async (uid: string) => {
    try {
      const all = await listCustomerMissions(uid);
      setMissions(all.filter((m) => m.type === "marketplace_delivery"));
    } catch {
      setMissions([]);
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    if (!userId) { setMissions([]); setLoaded(true); return; }
    reload(userId);
    const ch = supabase
      .channel(`buyer-deliveries-${userId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "missions", filter: `customer_id=eq.${userId}` },
        () => reload(userId),
      )
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [userId, reload]);

  const active = missions.filter((m) =>
    !isTerminalState(m.state) || (m.state === "delivered" && !m.customer_confirmed_at),
  );
  if (!loaded || active.length === 0) return null;

  const confirmReceived = async (id: string) => {
    setBusy(id);
    try {
      await customerConfirmDelivery(id);
      toast.success("Merci, livraison confirmée");
      if (userId) await reload(userId);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusy(null);
    }
  };

  return (
    <section className="space-y-2 mb-4">
      <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
        Mes livraisons Marché
      </h3>
      {active.map((m) => {
        const awaitingConfirm = m.state === "delivered" && !m.customer_confirmed_at;
        const showCode = !awaitingConfirm && m.customer_handoff_code;
        return (
          <div key={m.id} className="rounded-2xl border border-border/60 bg-card p-3 space-y-2">
            <div className="flex items-center justify-between">
              <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary">
                <ShieldCheck className="w-3.5 h-3.5" /> Livraison Marché
              </span>
              <span className="text-[10px] font-bold uppercase text-muted-foreground">
                {MISSION_STATE_LABEL[m.state]}
              </span>
            </div>
            {m.payload_summary && (
              <p className="text-sm text-foreground truncate">{m.payload_summary}</p>
            )}
            {showCode && (
              <div className="rounded-xl bg-primary/5 border border-primary/20 p-3 text-center">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground inline-flex items-center gap-1">
                  <KeyRound className="w-3 h-3" /> Code à donner au coursier
                </p>
                <p className="text-2xl font-bold tracking-[0.4em] text-primary tabular-nums mt-1">
                  {m.customer_handoff_code}
                </p>
              </div>
            )}
            {awaitingConfirm && (
              <Button
                className="w-full h-11"
                disabled={busy === m.id}
                onClick={() => confirmReceived(m.id)}
              >
                {busy === m.id ? <Loader2 className="w-4 h-4 animate-spin" /> : (<><Check className="w-4 h-4 mr-2" /> Confirmer la réception</>)}
              </Button>
            )}
          </div>
        );
      })}
    </section>
  );
}