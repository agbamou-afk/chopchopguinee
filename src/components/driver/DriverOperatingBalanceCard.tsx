import { Wallet, Lock, ShieldCheck, Plus, Info, Gift } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import {
  useDriverBalance,
  INSUFFICIENT_BALANCE_MESSAGE,
  STARTER_CREDIT_LABEL,
  STARTER_CREDIT_NOTE,
} from "@/lib/finance/driverBalance";
import { useOmTopupEnabled } from "@/lib/flags/useFeatureFlag";

/**
 * Driver Chop Pay wallet — ONE ledger wallet. Earnings, top-ups,
 * commission reserves, mission collateral and cashout holds all live in
 * the same balance; "held" simply means temporarily not withdrawable.
 */
export function DriverOperatingBalanceCard({ onTopUp }: { onTopUp?: () => void }) {
  const { summary, loading } = useDriverBalance();
  const topupOn = useOmTopupEnabled();

  const available = summary?.available_gnf ?? 0;
  const total = summary?.balance_gnf ?? 0;
  const held = summary?.held_gnf ?? 0;
  const collateral = summary?.collateral_held_gnf ?? 0;
  const commission = summary?.commission_held_gnf ?? 0;
  const promo = summary?.promo_available_gnf ?? 0;
  // Withdrawable NEVER includes the restricted starting credit.
  const withdrawable = summary?.withdrawable_gnf ?? Math.max(0, available - promo);
  const blocked = !loading && available <= 0;

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
          {INSUFFICIENT_BALANCE_MESSAGE}
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
