import { useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { repayCancellationDebt, useCancellationDebts } from "@/lib/finance/cancellation";

const MISSION_LABEL: Record<string, string> = {
  ride: "Course", bonbonna: "Bonbonna", repas: "Repas",
  marche: "Marché", envoyer: "Envoyer",
};

/**
 * Slice 8 — outstanding cancellation debt and explicit repayment.
 * Amounts, eligibility and collected totals are all server truth; the panel
 * never subtracts, sums or infers a restriction from a displayed amount.
 */
export function CancellationDebtPanel() {
  const { data, loading, reload } = useCancellationDebts();
  const [busyId, setBusyId] = useState<string | null>(null);

  if (loading || !data || data.outstanding_total_gnf <= 0) return null;

  const repay = async (debtId: string) => {
    setBusyId(debtId);
    try {
      const res = await repayCancellationDebt(debtId);
      if (res.status === "no_funds") {
        toast.error("Solde Chop Pay insuffisant. Rechargez puis réessayez.");
      } else if (res.fully_paid) {
        toast.success("Montant réglé. Les commandes en espèces sont de nouveau disponibles.");
      } else {
        toast.success(`Réglé : ${formatGNF(res.collected_gnf ?? 0)}. Reste ${formatGNF(res.outstanding_gnf ?? 0)}.`);
      }
      await reload();
    } catch {
      toast.error("Règlement impossible pour le moment.");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <section
      className="mx-4 mt-4 rounded-2xl border border-warning/40 bg-warning/5 p-3 space-y-2"
      aria-label="Frais d’annulation à régler"
    >
      <p className="text-[13px] font-semibold text-foreground inline-flex items-center gap-1.5">
        <AlertTriangle className="w-4 h-4 text-warning" />
        Frais d’annulation à régler
      </p>

      <p className="text-xl font-bold tabular-nums text-foreground">
        {formatGNF(data.outstanding_total_gnf)}
      </p>

      <p className="text-[11px] text-muted-foreground">
        {data.cash_orders_allowed
          ? "Aucun blocage en cours."
          : "Tant que ce montant n’est pas réglé, vous ne pouvez pas passer de nouvelle commande en espèces. Votre compte, votre historique, le support et les paiements Chop Pay restent disponibles."}
      </p>

      <ul className="space-y-1.5">
        {data.items.map((d) => (
          <li
            key={d.debt_id}
            className="flex items-center justify-between gap-2 rounded-xl bg-card border border-border/60 px-2.5 py-2"
          >
            <div className="min-w-0">
              <p className="text-[12px] font-medium text-foreground truncate">
                {MISSION_LABEL[d.mission_type] ?? d.mission_type}
              </p>
              <p className="text-[10px] text-muted-foreground">
                {new Date(d.created_at).toLocaleDateString("fr-FR")} · reste{" "}
                <span className="tabular-nums">{formatGNF(d.outstanding_gnf)}</span>
              </p>
            </div>
            <Button
              size="sm"
              variant="outline"
              className="h-7 text-[11px] shrink-0"
              disabled={busyId === d.debt_id}
              onClick={() => void repay(d.debt_id)}
            >
              {busyId === d.debt_id ? <Loader2 className="w-3 h-3 animate-spin" /> : "Régler"}
            </Button>
          </li>
        ))}
      </ul>

      <p className="text-[10px] text-muted-foreground">
        Le règlement est prélevé sur votre solde Chop Pay disponible ({formatGNF(data.available_gnf)}).
      </p>
    </section>
  );
}