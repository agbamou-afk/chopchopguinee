import { useEffect, useState } from "react";
import { Wallet, Lock, ShieldCheck, Plus, Info, Gift, History, CheckCircle2, Clock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import {
  useDriverBalance,
  fetchEligibility,
  type Eligibility,
  INSUFFICIENT_BALANCE_MESSAGE,
  STARTER_CREDIT_LABEL,
  STARTER_CREDIT_NOTE,
} from "@/lib/finance/driverBalance";
import { useOmTopupEnabled } from "@/lib/flags/useFeatureFlag";
import { useDriverTopupHistory } from "@/lib/finance/readModels";

/**
 * Driver Chop Pay wallet — ONE ledger wallet. Earnings, top-ups,
 * commission reserves, mission collateral and cashout holds all live in
 * the same balance; "held" simply means temporarily not withdrawable.
 */
export function DriverOperatingBalanceCard({ onTopUp }: { onTopUp?: () => void }) {
  const { summary, loading } = useDriverBalance();
  const topupOn = useOmTopupEnabled();
  const { rows: topups } = useDriverTopupHistory(5);
  const [eligibility, setEligibility] = useState<Eligibility | null>(null);

  // Mission eligibility comes from the canonical server finance rule path.
  useEffect(() => {
    let alive = true;
    void fetchEligibility("ride", 0).then((e) => { if (alive) setEligibility(e); });
    return () => { alive = false; };
  }, [summary?.balance_gnf, summary?.held_gnf]);

  const available = summary?.available_gnf ?? 0;
  const total = summary?.balance_gnf ?? 0;
  const held = summary?.held_gnf ?? 0;
  const collateral = summary?.collateral_held_gnf ?? 0;
  const commission = summary?.commission_held_gnf ?? 0;
  const promo = summary?.promo_available_gnf ?? 0;
  const promoTotal = summary?.promo_remaining_gnf ?? 0;
  const unrestricted = summary?.unrestricted_available_gnf ?? 0;
  // Withdrawable NEVER includes the restricted starting credit — server value only.
  const withdrawable = summary?.withdrawable_gnf ?? 0;
  const blocked = !loading && eligibility !== null && !eligibility.eligible;

  return (
    <div className="rounded-2xl border border-border/60 bg-card p-4">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl gradient-wallet flex items-center justify-center">
          <Wallet className="w-5 h-5 text-primary-foreground" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-xs text-muted-foreground">Portefeuille chauffeur · disponible</p>
          <p className="text-xl font-extrabold text-foreground tabular-nums">
            {loading ? "…" : formatGNF(available)}
          </p>
          <p className="text-[11px] text-muted-foreground tabular-nums">
            Total {formatGNF(total)} · retenu {formatGNF(held)}
          </p>
          <p className="text-[11px] text-muted-foreground tabular-nums">
            Fonds libres {formatGNF(unrestricted)} · crédit restreint {formatGNF(promoTotal)}
          </p>
          <p className="text-[11px] text-muted-foreground tabular-nums">
            Montant retirable {formatGNF(withdrawable)}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 mt-3">
        <div className="rounded-lg bg-muted/40 p-2">
          <p className="text-[10px] text-muted-foreground flex items-center gap-1">
            <Lock className="w-3 h-3" /> Caution retenue
          </p>
          <p className="text-xs font-bold text-foreground tabular-nums">{formatGNF(collateral)}</p>
        </div>
        <div className="rounded-lg bg-muted/40 p-2">
          <p className="text-[10px] text-muted-foreground flex items-center gap-1">
            <ShieldCheck className="w-3 h-3" /> Commission retenue
          </p>
          <p className="text-xs font-bold text-foreground tabular-nums">{formatGNF(commission)}</p>
        </div>
      </div>

      {promo > 0 && (
        <div className="mt-2 rounded-lg border border-primary/30 bg-primary/5 p-2">
          <p className="text-[10px] text-muted-foreground flex items-center gap-1">
            <Gift className="w-3 h-3" /> {STARTER_CREDIT_LABEL}
          </p>
          <p className="text-xs font-bold text-foreground tabular-nums">{formatGNF(promo)}</p>
          <p className="text-[10px] text-muted-foreground mt-1">{STARTER_CREDIT_NOTE}</p>
        </div>
      )}

      {blocked && (
        <div className="mt-3 rounded-xl border border-secondary/40 bg-secondary/10 p-3 text-xs text-foreground">
          <p>{INSUFFICIENT_BALANCE_MESSAGE}</p>
          {eligibility && (
            <p className="mt-1 text-[11px] text-muted-foreground tabular-nums">
              Requis {formatGNF(eligibility.required_gnf)} · manquant {formatGNF(eligibility.shortfall_gnf)}
            </p>
          )}
        </div>
      )}

      {eligibility?.eligible && (
        <p className="mt-3 text-[11px] text-muted-foreground inline-flex items-center gap-1.5">
          <CheckCircle2 className="w-3.5 h-3.5 text-success" />
          Éligible aux nouvelles missions (requis {formatGNF(eligibility.required_gnf)})
        </p>
      )}

      {topups.length > 0 && (
        <div className="mt-3 border-t border-border/60 pt-3">
          <p className="text-[11px] font-semibold text-foreground flex items-center gap-1.5 mb-1.5">
            <History className="w-3.5 h-3.5" /> Mes recharges
          </p>
          <div className="space-y-1.5">
            {topups.map((t) => (
              <div key={t.id} className="flex items-center gap-2">
                {t.credited
                  ? <CheckCircle2 className="w-3.5 h-3.5 text-success shrink-0" />
                  : <Clock className="w-3.5 h-3.5 text-muted-foreground shrink-0" />}
                <span className="text-[11px] text-foreground tabular-nums flex-1">
                  {formatGNF(t.amount_gnf)}
                </span>
                <span className="text-[10px] text-muted-foreground">
                  {t.credited ? "Créditée" : "En vérification"} ·{" "}
                  {new Date(t.created_at).toLocaleDateString("fr-FR")}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="mt-3 flex items-start gap-2 text-[11px] text-muted-foreground">
        <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" />
        <p>
          Un seul portefeuille : recharges et gains arrivent ici. Les montants
          « retenus » (caution de mission, commission, retrait en cours) ne sont
          pas retirables tant qu'ils ne sont pas libérés. Vous pouvez retirer le
          solde disponible ; s'il descend sous le minimum requis, les nouvelles
          missions se mettent en pause jusqu'à une recharge ou un nouveau gain.
        </p>
      </div>

      <Button
        size="sm"
        className="w-full mt-3"
        onClick={onTopUp}
        disabled={!topupOn || !onTopUp}
        title={topupOn ? undefined : "Rechargement Orange Money temporairement indisponible"}
      >
        <Plus className="w-4 h-4 mr-1" /> Recharger mon compte
      </Button>
    </div>
  );
}
