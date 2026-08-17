import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { Loader2, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/marche";
import {
  decideProposal,
  getProcurementMission,
  shopperErrorFr,
  LINE_STATE_LABEL_FR,
  MISSION_STATE_LABEL_FR,
  type ShopperMission,
} from "@/lib/marche/shopper";

/**
 * Node 4 R7 — customer view of an authorized basket being shopped.
 * Read-only except for the one thing the customer owns: approving or refusing
 * a replacement proposed by the shopper.
 */
export function ProcurementMissionTracker({ requestId }: { requestId: string }) {
  const [mission, setMission] = useState<ShopperMission | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    try {
      setMission(await getProcurementMission(requestId));
    } catch {
      setMission(null);
    } finally {
      setLoading(false);
    }
  }, [requestId]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const decide = async (lineNo: number, version: number, decision: "approve" | "reject") => {
    setBusy(true);
    try {
      await decideProposal({ requestId, lineNo, version, decision });
      toast.success(decision === "approve" ? "Remplacement accepté" : "Remplacement refusé");
      await reload();
    } catch (e) {
      toast.error(shopperErrorFr((e as Error)?.message ?? ""));
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <Loader2 className="w-3.5 h-3.5 animate-spin" /> Chargement du suivi…
      </div>
    );
  }
  if (!mission) {
    return (
      <p className="text-xs text-muted-foreground">
        Aucun acheteur n'a encore pris ce panier.
      </p>
    );
  }

  return (
    <div className="space-y-3" data-testid="procurement-mission-tracker">
      <div className="rounded-xl border border-border/60 bg-card p-3 space-y-1">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Statut</span>
          <span className="font-semibold">{MISSION_STATE_LABEL_FR[mission.state]}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Montant maximum autorisé</span>
          <span className="font-bold">{formatGNF(mission.authorized_ceiling_gnf)}</span>
        </div>
        {mission.verified_spend_gnf !== null && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Dépense réelle vérifiée</span>
            <span className="font-bold">{formatGNF(mission.verified_spend_gnf)}</span>
          </div>
        )}
      </div>

      <div className="space-y-2">
        {mission.lines.map((l) => (
          <div key={l.line_no} className="rounded-xl border border-border/60 bg-card p-3 space-y-2">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="text-sm font-medium truncate">
                  {l.commodity_name_fr} · {l.variant_name_fr}
                </p>
                <p className="text-[11px] text-muted-foreground truncate">
                  {l.requested_qty} × {l.option_label_fr}
                </p>
              </div>
              <span className="text-[10px] font-semibold text-muted-foreground shrink-0">
                {LINE_STATE_LABEL_FR[l.state]}
              </span>
            </div>

            {l.state === "acquired" && (
              <p className="text-[11px] text-muted-foreground">
                {formatGNF(l.actual_line_total_gnf ?? 0)}
                {l.substitute_label_fr ? ` · remplacé par ${l.substitute_label_fr}` : ""}
              </p>
            )}
            {l.state === "unavailable" && (
              <p className="text-[11px] text-muted-foreground">
                Introuvable au marché — cet article ne vous sera pas facturé.
              </p>
            )}

            {l.pending_proposal && (
              <div className="rounded-lg border border-primary/40 bg-primary/5 p-2.5 space-y-2">
                <p className="text-[11px] font-semibold text-foreground">
                  L'acheteur propose : {l.substitute_label_fr ?? "un remplacement"}
                </p>
                <div className="flex gap-2">
                  <Button size="sm" className="flex-1" disabled={busy}
                    onClick={() => decide(l.line_no, l.pending_proposal!.version, "approve")}>
                    Accepter
                  </Button>
                  <Button size="sm" variant="outline" className="flex-1" disabled={busy}
                    onClick={() => decide(l.line_no, l.pending_proposal!.version, "reject")}>
                    Refuser
                  </Button>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>

      <p className="text-[11px] text-muted-foreground flex items-start gap-1">
        <ShieldCheck className="w-3 h-3 mt-0.5 shrink-0" />
        Seule la dépense réelle vérifiée est débitée, dans la limite du montant autorisé. Le reste
        est libéré automatiquement.
      </p>
    </div>
  );
}
