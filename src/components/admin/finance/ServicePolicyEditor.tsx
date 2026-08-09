import { useMemo, useState } from "react";
import { History, CalendarClock } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { PolicyConfirmDialog } from "./PolicyConfirmDialog";
import {
  BASIS_OPTIONS, BPS_FIELDS, EditableField, FIELD_LABELS, FinancePolicyRow, MissionType,
  MISSION_LABELS, claimExposureBps, currentPolicy, diffPolicy, FIELDS_BY_SERVICE,
  fmtDateTime, formatFieldValue, historyPolicies, scheduledPolicies,
} from "@/lib/admin/financePolicy";

interface Props {
  missionType: MissionType;
  rows: FinancePolicyRow[];
  canEdit: boolean;
  onSaved: () => void;
}

function defaultEffectiveFrom() {
  const d = new Date(Date.now() + 60 * 60 * 1000);
  d.setSeconds(0, 0);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function ServicePolicyEditor({ missionType, rows, canEdit, onSaved }: Props) {
  const fields = FIELDS_BY_SERVICE[missionType];
  const current = currentPolicy(rows, missionType);
  const scheduled = scheduledPolicies(rows, missionType);
  const history = historyPolicies(rows, missionType);

  const [draft, setDraft] = useState<Partial<Record<EditableField, unknown>>>({});
  const [effectiveFrom, setEffectiveFrom] = useState(defaultEffectiveFrom());
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [showHistory, setShowHistory] = useState(false);

  const valueOf = (f: EditableField) =>
    draft[f] !== undefined
      ? draft[f]
      : current
        ? (current as unknown as Record<string, unknown>)[f]
        : null;

  const diff = useMemo(() => diffPolicy(current, draft, fields), [current, draft, fields]);

  const exposureBps = claimExposureBps(Number(valueOf("collateral_pct_bps") ?? 0));

  const save = async (reason: string) => {
    setSaving(true);
    const num = (f: EditableField, fallback: number | null = null) => {
      const v = valueOf(f);
      return v === null || v === undefined || v === "" ? fallback : Number(v);
    };
    const str = (f: EditableField, fallback: string | null = null) => {
      const v = valueOf(f);
      return v === null || v === undefined || v === "" ? fallback : String(v);
    };
    const { error } = await supabase.rpc("admin_set_finance_policy", {
      p_mission_type: missionType,
      p_commission_bps: num("commission_bps", 0) as number,
      p_min_driver_balance_gnf: num("min_driver_balance_gnf", 0) as number,
      p_collateral_mode: str("collateral_mode", "none") as string,
      p_collateral_pct_bps: num("collateral_pct_bps", 0) as number,
      p_collateral_fixed_gnf: 0,
      p_collateral_min_gnf: num("collateral_min_gnf", 0) as number,
      p_collateral_max_gnf: num("collateral_max_gnf"),
      p_fixed_commission_gnf: num("fixed_commission_gnf", 0) as number,
      p_require_collateral_before_offer: current?.require_collateral_before_offer ?? false,
      p_effective_from: new Date(effectiveFrom).toISOString(),
      p_note: reason,
      p_collateral_basis: str("collateral_basis"),
      p_transaction_fee_bps: num("transaction_fee_bps"),
      p_fee_basis: str("fee_basis"),
      p_cancel_before_dispatch_bps: num("cancel_before_dispatch_bps"),
      p_cancel_after_dispatch_bps: num("cancel_after_dispatch_bps"),
      p_cancel_basis: str("cancel_basis"),
      p_cash_funding_mode: str("cash_funding_mode"),
      p_cash_funding_pct_bps: num("cash_funding_pct_bps"),
      p_cash_funding_max_gnf: null,
      p_max_declared_value_gnf: num("max_declared_value_gnf"),
      p_claims_exposure_max_gnf: num("claims_exposure_max_gnf"),
    });
    setSaving(false);
    if (error) {
      toast({ title: "Refusé par le serveur", description: error.message, variant: "destructive" });
      return;
    }
    toast({
      title: "Politique programmée",
      description: `${MISSION_LABELS[missionType]} — applicable à partir du ${fmtDateTime(new Date(effectiveFrom).toISOString())}.`,
    });
    setConfirmOpen(false);
    setDraft({});
    onSaved();
  };

  return (
    <div className="space-y-3">
      <Card className="p-4 space-y-1">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <h3 className="font-bold">{MISSION_LABELS[missionType]}</h3>
          <Badge variant={current ? "secondary" : "destructive"}>
            {current ? `En vigueur depuis ${fmtDateTime(current.effective_from)}` : "Aucune politique active"}
          </Badge>
        </div>
        {scheduled.length > 0 && (
          <p className="text-[11px] flex items-center gap-1 text-secondary-foreground">
            <CalendarClock className="w-3 h-3" />
            Prochaine politique programmée : {fmtDateTime(scheduled[0].effective_from)}
            {scheduled.length > 1 ? ` (+${scheduled.length - 1} autre(s))` : ""}
          </p>
        )}
        {current && (
          <div className="grid sm:grid-cols-2 gap-x-4 gap-y-0.5 pt-2 text-[11px] text-muted-foreground">
            {fields.map((f) => (
              <div key={f} className="flex justify-between gap-2">
                <span>{FIELD_LABELS[f]}</span>
                <span className="font-mono text-foreground">
                  {formatFieldValue(f, (current as unknown as Record<string, unknown>)[f])}
                </span>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card className="p-4 space-y-3">
        <p className="text-xs font-semibold">Programmer une nouvelle politique (transactions futures)</p>
        <div className="grid sm:grid-cols-2 gap-3">
          {fields.map((f) => {
            const options = BASIS_OPTIONS[f];
            return (
              <div key={f}>
                <Label className="text-xs">{FIELD_LABELS[f]}</Label>
                {options ? (
                  <select
                    className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                    disabled={!canEdit}
                    value={String(valueOf(f) ?? "none")}
                    onChange={(e) => setDraft((p) => ({ ...p, [f]: e.target.value }))}
                  >
                    {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </select>
                ) : (
                  <Input
                    type="number"
                    min={0}
                    step={BPS_FIELDS.includes(f) ? 0.25 : 1}
                    disabled={!canEdit}
                    value={
                      valueOf(f) === null || valueOf(f) === undefined
                        ? ""
                        : BPS_FIELDS.includes(f)
                          ? String(Number(valueOf(f)) / 100)
                          : String(valueOf(f))
                    }
                    onChange={(e) => {
                      const raw = e.target.value;
                      setDraft((p) => ({
                        ...p,
                        [f]: raw === ""
                          ? null
                          : BPS_FIELDS.includes(f) ? Math.round(Number(raw) * 100) : Number(raw),
                      }));
                    }}
                  />
                )}
              </div>
            );
          })}
          <div>
            <Label className="text-xs">Date d'effet</Label>
            <Input
              type="datetime-local"
              disabled={!canEdit}
              value={effectiveFrom}
              onChange={(e) => setEffectiveFrom(e.target.value)}
            />
          </div>
        </div>

        {missionType === "envoyer" && (
          <p className="text-[11px] text-muted-foreground">
            Exposition sinistres CHOPCHOP dérivée : {(exposureBps / 100).toFixed(2)} % de la valeur déclarée
            acceptée (reste après la caution coursier). Réserve d'enquête — ce n'est pas une assurance automatique.
          </p>
        )}

        <div className="flex items-center gap-2">
          <Button size="sm" disabled={!canEdit || diff.length === 0} onClick={() => setConfirmOpen(true)}>
            Vérifier et programmer
          </Button>
          <Button size="sm" variant="ghost" disabled={diff.length === 0} onClick={() => setDraft({})}>
            Réinitialiser
          </Button>
          <span className="text-[11px] text-muted-foreground">
            {diff.length === 0 ? "Aucune modification" : `${diff.length} champ(s) modifié(s)`}
          </span>
        </div>
      </Card>

      <Card className="p-4">
        <button
          className="text-xs font-semibold flex items-center gap-1"
          onClick={() => setShowHistory((v) => !v)}
        >
          <History className="w-3.5 h-3.5" />
          Historique immuable ({history.length})
        </button>
        {showHistory && (
          <div className="mt-2 divide-y text-[11px]">
            {history.map((h) => (
              <div key={h.id} className="py-1.5">
                <p className="font-mono">{fmtDateTime(h.effective_from)}</p>
                <p className="text-muted-foreground">
                  commission {formatFieldValue("commission_bps", h.commission_bps)} ·
                  caution {formatFieldValue("collateral_pct_bps", h.collateral_pct_bps)} ({h.collateral_basis}) ·
                  frais {formatFieldValue("transaction_fee_bps", h.transaction_fee_bps)} ({h.fee_basis}) ·
                  annulation {formatFieldValue("cancel_before_dispatch_bps", h.cancel_before_dispatch_bps)}/
                  {formatFieldValue("cancel_after_dispatch_bps", h.cancel_after_dispatch_bps)} ({h.cancel_basis})
                </p>
                {h.note && <p className="italic text-muted-foreground">« {h.note} »</p>}
              </div>
            ))}
          </div>
        )}
      </Card>

      <PolicyConfirmDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        title={`Modifier la politique — ${MISSION_LABELS[missionType]}`}
        effectiveFrom={fmtDateTime(new Date(effectiveFrom).toISOString())}
        diff={diff}
        saving={saving}
        onConfirm={save}
      />
    </div>
  );
}
