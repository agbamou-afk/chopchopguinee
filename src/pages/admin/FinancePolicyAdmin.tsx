import { useCallback, useEffect, useState } from "react";
import { Loader2, ShieldAlert } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/format";

type Policy = {
  id: string;
  mission_type: string;
  commission_bps: number;
  fixed_commission_gnf: number;
  min_driver_balance_gnf: number;
  collateral_mode: string;
  collateral_pct_bps: number;
  collateral_fixed_gnf: number;
  collateral_min_gnf: number;
  collateral_max_gnf: number | null;
  require_collateral_before_offer: boolean;
  effective_from: string;
  enabled: boolean;
  note: string | null;
};

const MISSION_TYPES = ["ride", "bonbonna", "repas", "marche", "envoyer"] as const;
const LABELS: Record<string, string> = {
  ride: "Course Moto",
  bonbonna: "Bonbonna",
  repas: "Repas",
  marche: "Marché",
  envoyer: "Envoyer",
};

/**
 * Canonical finance-policy surface. Server enforces God Admin write via
 * `admin_set_finance_policy`; this page is read-only for everyone else.
 * No value here is authoritative — the RPC recomputes and audits.
 */
export default function FinancePolicyAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [rows, setRows] = useState<Policy[]>([]);
  const [loading, setLoading] = useState(true);
  const [draft, setDraft] = useState<Record<string, Partial<Policy>>>({});
  const [saving, setSaving] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase
      .from("finance_policies")
      .select("*")
      .order("mission_type")
      .order("effective_from", { ascending: false });
    setRows((data ?? []) as Policy[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const currentFor = (t: string) =>
    rows.find((r) => r.mission_type === t && r.enabled && new Date(r.effective_from) <= new Date());
  const upcomingFor = (t: string) =>
    rows.filter((r) => r.mission_type === t && new Date(r.effective_from) > new Date());

  const save = async (t: string) => {
    const cur = currentFor(t);
    const d = draft[t] ?? {};
    setSaving(t);
    const { error } = await supabase.rpc("admin_set_finance_policy" as never, {
      p_mission_type: t,
      p_commission_bps: Number(d.commission_bps ?? cur?.commission_bps ?? 1000),
      p_min_driver_balance_gnf: Number(d.min_driver_balance_gnf ?? cur?.min_driver_balance_gnf ?? 0),
      p_collateral_mode: String(d.collateral_mode ?? cur?.collateral_mode ?? "none"),
      p_collateral_pct_bps: Number(d.collateral_pct_bps ?? cur?.collateral_pct_bps ?? 0),
      p_collateral_fixed_gnf: Number(d.collateral_fixed_gnf ?? cur?.collateral_fixed_gnf ?? 0),
      p_collateral_min_gnf: Number(d.collateral_min_gnf ?? cur?.collateral_min_gnf ?? 0),
      p_collateral_max_gnf: d.collateral_max_gnf ?? cur?.collateral_max_gnf ?? null,
      p_fixed_commission_gnf: Number(d.fixed_commission_gnf ?? cur?.fixed_commission_gnf ?? 0),
      p_require_collateral_before_offer: Boolean(
        d.require_collateral_before_offer ?? cur?.require_collateral_before_offer ?? false,
      ),
      p_note: d.note ?? null,
    } as never);
    setSaving(null);
    if (error) {
      toast({ title: "Refusé", description: error.message });
      return;
    }
    toast({ title: "Politique enregistrée", description: `${LABELS[t]} — audité, applicable aux missions futures.` });
    setDraft((p) => ({ ...p, [t]: {} }));
    void load();
  };

  return (
    <ModulePage
      module="pricing"
      title="Politique financière"
      subtitle="Commission et caution par type de mission — écriture réservée au God Admin"
    >
      {!isSuperAdmin && (
        <Card className="p-3 mb-3 flex items-center gap-2 text-xs text-muted-foreground">
          <ShieldAlert className="w-4 h-4" />
          Lecture seule. Seul un God Admin peut modifier la politique financière.
        </Card>
      )}

      {loading ? (
        <Loader2 className="w-5 h-5 animate-spin" />
      ) : (
        <div className="grid lg:grid-cols-2 gap-3">
          {MISSION_TYPES.map((t) => {
            const cur = currentFor(t);
            const d = draft[t] ?? {};
            const up = upcomingFor(t);
            const setField = (k: keyof Policy, v: unknown) =>
              setDraft((p) => ({ ...p, [t]: { ...(p[t] ?? {}), [k]: v } }));
            return (
              <Card key={t} className="p-4 space-y-3">
                <div className="flex items-baseline justify-between">
                  <h3 className="font-bold">{LABELS[t]}</h3>
                  <span className="text-[11px] text-muted-foreground">
                    {cur ? `En vigueur depuis ${new Date(cur.effective_from).toLocaleDateString("fr-FR")}` : "Aucune politique active"}
                  </span>
                </div>

                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <Label className="text-xs">Commission (%)</Label>
                    <Input
                      type="number" min={0} max={50} step={0.5} disabled={!isSuperAdmin}
                      value={String((d.commission_bps ?? cur?.commission_bps ?? 0) / 100)}
                      onChange={(e) => setField("commission_bps", Math.round(Number(e.target.value) * 100))}
                    />
                  </div>
                  <div>
                    <Label className="text-xs">Solde minimum (GNF)</Label>
                    <Input
                      type="number" min={0} disabled={!isSuperAdmin}
                      value={String(d.min_driver_balance_gnf ?? cur?.min_driver_balance_gnf ?? 0)}
                      onChange={(e) => setField("min_driver_balance_gnf", Number(e.target.value))}
                    />
                  </div>
                  <div>
                    <Label className="text-xs">Mode de caution</Label>
                    <select
                      className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                      disabled={!isSuperAdmin}
                      value={String(d.collateral_mode ?? cur?.collateral_mode ?? "none")}
                      onChange={(e) => setField("collateral_mode", e.target.value)}
                    >
                      <option value="none">Aucune</option>
                      <option value="fixed">Fixe</option>
                      <option value="percentage">Pourcentage</option>
                    </select>
                  </div>
                  <div>
                    <Label className="text-xs">Caution (%)</Label>
                    <Input
                      type="number" min={0} max={100} disabled={!isSuperAdmin}
                      value={String((d.collateral_pct_bps ?? cur?.collateral_pct_bps ?? 0) / 100)}
                      onChange={(e) => setField("collateral_pct_bps", Math.round(Number(e.target.value) * 100))}
                    />
                  </div>
                  <div>
                    <Label className="text-xs">Caution min (GNF)</Label>
                    <Input
                      type="number" min={0} disabled={!isSuperAdmin}
                      value={String(d.collateral_min_gnf ?? cur?.collateral_min_gnf ?? 0)}
                      onChange={(e) => setField("collateral_min_gnf", Number(e.target.value))}
                    />
                  </div>
                  <div>
                    <Label className="text-xs">Caution max (GNF)</Label>
                    <Input
                      type="number" min={0} disabled={!isSuperAdmin}
                      value={String(d.collateral_max_gnf ?? cur?.collateral_max_gnf ?? "")}
                      onChange={(e) => setField("collateral_max_gnf", e.target.value === "" ? null : Number(e.target.value))}
                    />
                  </div>
                </div>

                {cur && (
                  <p className="text-[11px] text-muted-foreground">
                    Actuel : {(cur.commission_bps / 100).toFixed(1)} % de commission ·
                    caution {cur.collateral_mode === "none" ? "aucune" : `${(cur.collateral_pct_bps / 100).toFixed(0)} %`} ·
                    solde min {formatGNF(cur.min_driver_balance_gnf)}
                  </p>
                )}
                {up.length > 0 && (
                  <p className="text-[11px] text-secondary-foreground">
                    {up.length} politique(s) programmée(s) — la prochaine le{" "}
                    {new Date(up[up.length - 1].effective_from).toLocaleDateString("fr-FR")}
                  </p>
                )}

                <Button
                  size="sm" className="w-full"
                  disabled={!isSuperAdmin || saving === t}
                  onClick={() => save(t)}
                >
                  {saving === t ? "Enregistrement…" : "Enregistrer (missions futures)"}
                </Button>
              </Card>
            );
          })}
        </div>
      )}

      <p className="text-[11px] text-muted-foreground mt-4">
        Les missions déjà acceptées conservent la politique enregistrée au moment
        de l'acceptation. Aucune modification n'est rétroactive.
      </p>
    </ModulePage>
  );
}
