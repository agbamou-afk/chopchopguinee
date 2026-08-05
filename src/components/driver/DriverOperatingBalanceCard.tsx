import { Wallet, Lock, ShieldCheck, Plus, Info } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import { useDriverBalance, INSUFFICIENT_BALANCE_MESSAGE } from "@/lib/finance/driverBalance";
import { useOmTopupEnabled } from "@/lib/flags/useFeatureFlag";

/**
 * Driver operating balance — funds CHOPCHOP commission and mission
 * collateral. Deliberately separated from personal earnings so a driver
 * never confuses reserved funds with withdrawable income.
 */
export function DriverOperatingBalanceCard({ onTopUp }: { onTopUp?: () => void }) {
  const { summary, loading } = useDriverBalance();
  const topupOn = useOmTopupEnabled();

  const available = summary?.available_gnf ?? 0;
  const collateral = summary?.collateral_held_gnf ?? 0;
  const commission = summary?.commission_held_gnf ?? 0;
  const blocked = !loading && available <= 0;

  return (
    <div className="rounded-2xl border border-border/60 bg-card p-4">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl gradient-wallet flex items-center justify-center">
          <Wallet className="w-5 h-5 text-primary-foreground" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-xs text-muted-foreground">Solde chauffeur · disponible</p>
          <p className="text-xl font-extrabold text-foreground tabular-nums">
            {loading ? "…" : formatGNF(available)}
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
            <ShieldCheck className="w-3 h-3" /> Réserve de commission
          </p>
          <p className="text-xs font-bold text-foreground tabular-nums">{formatGNF(commission)}</p>
        </div>
      </div>

      {blocked && (
        <div className="mt-3 rounded-xl border border-secondary/40 bg-secondary/10 p-3 text-xs text-foreground">
          {INSUFFICIENT_BALANCE_MESSAGE}
        </div>
      )}

      <div className="mt-3 flex items-start gap-2 text-[11px] text-muted-foreground">
        <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" />
        <p>
          Ce solde sert à la commission CHOPCHOP et à la caution des missions.
          Vos gains restent séparés et retirables selon la politique en vigueur.
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
