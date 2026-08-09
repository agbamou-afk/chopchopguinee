import { useCallback, useEffect, useMemo, useState } from "react";
import { CalendarClock, GitBranch, History, Loader2, Lock } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { useAuth } from "@/contexts/AuthContext";
import { PolicyConfirmDialog } from "./PolicyConfirmDialog";
import { FlagConfirmDialog } from "./FlagConfirmDialog";
import {
  DiffSpec, diffRecords, fmtDateTime, predecessorRow,
} from "@/lib/admin/financePolicy";

/**
 * Every canonical financial flag that exists after Slice 2. Flags are never
 * mutated by a table write: `admin_set_feature_flag` is the single audited path.
 */
const FINANCE_FLAGS: { key: string; label: string; hint: string; consequential?: boolean }[] = [
  { key: "om_topup_enabled", label: "Rechargement Orange Money", hint: "Étape 1 — actif au lancement", consequential: true },
  { key: "chop_pay_enabled", label: "Chop Pay (produit public)", hint: "Étape 2", consequential: true },
  { key: "chop_pay_balance_enabled", label: "Chop Pay — solde visible", hint: "Étape 2", consequential: true },
  { key: "driver_balance_gate_enabled", label: "Blocage offres sur solde chauffeur", hint: "Étape 3", consequential: true },
  { key: "driver_starter_credit_enabled", label: "Bonus de démarrage chauffeur", hint: "Étape 4", consequential: true },
  { key: "chop_pay_checkout_enabled", label: "Paiement Chop Pay", hint: "Étape 5", consequential: true },
  { key: "chop_pay_ecosystem_spend_enabled", label: "Dépense écosystème Chop Pay", hint: "Étape 5", consequential: true },
  { key: "cash_order_funding_enabled", label: "Financement commandes espèces", hint: "Étape 6", consequential: true },
  { key: "merchant_wallet_enabled", label: "Portefeuille marchand", hint: "Étape 7", consequential: true },
  { key: "merchant_om_settlement_enabled", label: "Règlement marchand Orange Money", hint: "Étape 7", consequential: true },
  { key: "driver_cashout_enabled", label: "Retrait chauffeur", hint: "Étape 8", consequential: true },
  { key: "om_payout_reconciliation_enabled", label: "Réconciliation des versements OM", hint: "Étape 8", consequential: true },
  { key: "non_ride_transaction_fee_enabled", label: "Frais de transaction hors course", hint: "Étape 9", consequential: true },
  { key: "cancellation_policy_enabled", label: "Politique d'annulation facturée", hint: "Étape 9", consequential: true },
  { key: "envoyer_claims_enabled", label: "Sinistres Envoyer", hint: "Étape 10", consequential: true },
  { key: "chop_pay_p2p_enabled", label: "Transferts P2P", hint: "Hors périmètre lancement", consequential: true },
  { key: "om_direct_checkout_enabled", label: "Paiement direct Orange Money", hint: "Archivé", consequential: true },
];

type Row = Record<string, unknown> & { effective_from: string };

function defaultEffectiveFrom() {
  const d = new Date(Date.now() + 60 * 60 * 1000);
  d.setSeconds(0, 0);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

const gnf = (v: unknown) =>
  v === null || v === undefined || v === "" ? "Non configuré" : `${Number(v).toLocaleString("fr-FR")} GNF`;
const bps = (v: unknown) =>
  v === null || v === undefined || v === "" ? "Non configuré" : `${(Number(v) / 100).toFixed(2)} %`;
const plain = (suffix = "") => (v: unknown) =>
  v === null || v === undefined || v === "" ? "Non configuré" : `${v}${suffix}`;
const bool = (v: unknown) => (v === null || v === undefined ? "Non configuré" : v ? "Oui" : "Non");

const CADENCES = [
  { value: "", label: "Non configuré" },
  { value: "daily", label: "Quotidien" },
  { value: "weekly", label: "Hebdomadaire" },
  { value: "biweekly", label: "Bimensuel" },
  { value: "monthly", label: "Mensuel" },
  { value: "on_demand", label: "À la demande" },
];
const cadenceLabel = (v: unknown) =>
  CADENCES.find((c) => c.value === (v ?? ""))?.label ?? String(v);

export function FinanceControlsPanel({ isGodAdmin }: { isGodAdmin: boolean }) {
  const { roles } = useAuth();
  const isFinanceAdmin = roles.includes("finance_admin");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [flags, setFlags] = useState<{ key: string; enabled: boolean }[]>([]);
  const [starterRows, setStarterRows] = useState<Row[]>([]);
  const [payoutRows, setPayoutRows] = useState<Row[]>([]);
  const [settlementRows, setSettlementRows] = useState<Row[]>([]);
  const [feeRows, setFeeRows] = useState<Row[]>([]);
  const [delegated, setDelegated] = useState(false);
  const [pendingFlag, setPendingFlag] = useState<{ key: string; label: string; value: boolean } | null>(null);

  // Per-section draft + effective date + confirm state.
  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [eff, setEff] = useState<Record<string, string>>({
    starter: defaultEffectiveFrom(), payout: defaultEffectiveFrom(),
    ms: defaultEffectiveFrom(), pf: defaultEffectiveFrom(),
  });
  const [confirm, setConfirm] = useState<string | null>(null);
  const [showHistory, setShowHistory] = useState<Record<string, boolean>>({});

  const load = useCallback(async () => {
    setLoading(true);
    const [f, sc, pp, ms, pf, del] = await Promise.all([
      supabase.from("feature_flags").select("key,enabled"),
      supabase.from("driver_starter_credit_policies").select("*").order("effective_from", { ascending: false }),
      supabase.from("driver_payout_policies").select("*").order("effective_from", { ascending: false }),
      supabase.from("merchant_settlement_policies").select("*").order("effective_from", { ascending: false }),
      supabase.from("provider_fee_schedules").select("*").eq("provider", "orange_money").order("effective_from", { ascending: false }),
      supabase.from("app_settings").select("value").eq("key", "finance_delegation").maybeSingle(),
    ]);
    setFlags((f.data ?? []) as { key: string; enabled: boolean }[]);
    setStarterRows((sc.data ?? []) as unknown as Row[]);
    setPayoutRows((pp.data ?? []) as unknown as Row[]);
    setSettlementRows((ms.data ?? []) as unknown as Row[]);
    setFeeRows((pf.data ?? []) as unknown as Row[]);
    const v = del.data?.value as { provider_fee_to_finance_admin?: boolean } | null;
    setDelegated(Boolean(v?.provider_fee_to_finance_admin));
    setDraft({});
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const at = (k: string) => new Date(eff[k]);
  // Base = row in force immediately before the chosen effective time (may be scheduled).
  const starterBase = useMemo(() => predecessorRow(starterRows, at("starter")), [starterRows, eff]);
  const payoutBase = useMemo(() => predecessorRow(payoutRows, at("payout")), [payoutRows, eff]);
  const msBase = useMemo(() => predecessorRow(settlementRows, at("ms")), [settlementRows, eff]);
  const pfBase = useMemo(() => predecessorRow(feeRows, at("pf")), [feeRows, eff]);

  const activeOf = (rows: Row[]) => predecessorRow(rows, new Date(Date.now() + 1000));
  const scheduledOf = (rows: Row[]) =>
    rows.filter((r) => new Date(r.effective_from) > new Date()).sort(
      (a, b) => +new Date(a.effective_from) - +new Date(b.effective_from));

  /** Draft value, falling back to the predecessor. `null` means deliberately unset. */
  const valueOf = (key: string, base: Row | undefined) =>
    key in draft ? draft[key] : (base?.[key] ?? null);

  const setVal = (key: string, v: unknown) => setDraft((p) => ({ ...p, [key]: v }));

  /** Numeric input that preserves null instead of coercing a blank to zero. */
  const numField = (key: string, label: string, base: Row | undefined, disabled: boolean, hint?: string) => (
    <div key={key}>
      <Label className="text-xs">{label}</Label>
      <Input
        type="number" min={0} disabled={disabled}
        placeholder="Non configuré"
        value={valueOf(key, base) === null || valueOf(key, base) === undefined ? "" : String(valueOf(key, base))}
        onChange={(e) => setVal(key, e.target.value === "" ? null : Number(e.target.value))}
      />
      {hint && <p className="text-[10px] text-muted-foreground mt-0.5">{hint}</p>}
    </div>
  );

  const baseBanner = (k: string, base: Row | undefined, rows: Row[]) => {
    const active = activeOf(rows);
    const isScheduledBase = !!base && (!active || base.id !== active.id);
    return (
      <div className="flex items-start gap-1.5 text-[11px] rounded-md bg-muted p-2">
        <GitBranch className="w-3.5 h-3.5 mt-px shrink-0" />
        {base ? (
          <span>
            Base héritée : <strong>{isScheduledBase ? "politique programmée" : "politique en vigueur"} du{" "}
            {fmtDateTime(base.effective_from)}</strong>
            {isScheduledBase && " — la date d'effet choisie suit une politique déjà programmée."}
          </span>
        ) : (
          <span>Aucune politique antérieure : les valeurs doivent être renseignées explicitement.</span>
        )}
      </div>
    );
  };

  const effField = (k: string, disabled: boolean) => (
    <div>
      <Label className="text-xs">Date d'effet</Label>
      <Input
        type="datetime-local" disabled={disabled} value={eff[k]}
        onChange={(e) => setEff((p) => ({ ...p, [k]: e.target.value }))}
      />
    </div>
  );

  const scheduledLine = (rows: Row[], render: (r: Row) => string) => {
    const s = scheduledOf(rows);
    if (s.length === 0) return null;
    return (
      <p className="text-[11px] flex items-center gap-1">
        <CalendarClock className="w-3 h-3" />
        Programmé : {fmtDateTime(s[0].effective_from)} — {render(s[0])}
        {s.length > 1 ? ` (+${s.length - 1})` : ""}
      </p>
    );
  };

  const historyBlock = (k: string, rows: Row[], render: (r: Row) => string) => (
    <div>
      <button
        className="text-[11px] font-semibold flex items-center gap-1"
        onClick={() => setShowHistory((p) => ({ ...p, [k]: !p[k] }))}
      >
        <History className="w-3 h-3" /> Historique immuable ({rows.length})
      </button>
      {showHistory[k] && (
        <div className="mt-1 divide-y text-[11px]">
          {rows.map((r) => (
            <div key={String(r.id)} className="py-1">
              <span className="font-mono">{fmtDateTime(r.effective_from)}</span> — {render(r)}
              {r.note ? <span className="italic text-muted-foreground"> « {String(r.note)} »</span> : null}
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const run = async (
    fn: () => PromiseLike<{ error: { message: string } | null }>, okMsg: string,
  ) => {
    setSaving(true);
    const { error } = await fn();
    setSaving(false);
    if (error) { toast({ title: "Refusé par le serveur", description: error.message, variant: "destructive" }); return; }
    toast({ title: okMsg });
    setConfirm(null);
    void load();
  };

  if (loading) return <Loader2 className="w-5 h-5 animate-spin" />;

  const flagOn = (k: string) => flags.find((x) => x.key === k)?.enabled ?? false;
  const canPf = isGodAdmin || (isFinanceAdmin && delegated);

  // ---- diff specs -----------------------------------------------------
  const STARTER_SPECS: DiffSpec[] = [
    { key: "amount_gnf", label: "Montant du bonus", format: gnf },
    { key: "enabled", label: "Programme actif", format: bool },
  ];
  const PAYOUT_SPECS: DiffSpec[] = [
    { key: "min_request_gnf", label: "Minimum", format: gnf },
    { key: "max_request_gnf", label: "Maximum", format: gnf },
    { key: "daily_limit_gnf", label: "Plafond quotidien", format: gnf },
    { key: "cancel_window_seconds", label: "Fenêtre d'annulation", format: plain(" s") },
    { key: "processing_estimate_min_minutes", label: "Délai min", format: plain(" min") },
    { key: "processing_estimate_max_minutes", label: "Délai max", format: plain(" min") },
    { key: "provider_fee_passthrough", label: "Frais opérateur répercutés", format: bool },
  ];
  const MS_SPECS: DiffSpec[] = [
    { key: "configured", label: "Infrastructure configurée", format: bool },
    { key: "cadence", label: "Cadence", format: cadenceLabel },
    { key: "min_settlement_gnf", label: "Règlement minimum", format: gnf },
    { key: "max_settlement_gnf", label: "Règlement maximum", format: gnf },
    { key: "fee_bps", label: "Frais", format: bps },
    { key: "fee_fixed_gnf", label: "Frais fixes", format: gnf },
    { key: "fee_passthrough", label: "Frais répercutés", format: bool },
  ];
  const PF_SPECS: DiffSpec[] = [
    { key: "fee_bps", label: "Frais opérateur", format: bps },
    { key: "fee_fixed_gnf", label: "Frais fixes", format: gnf },
    { key: "min_fee_gnf", label: "Frais minimum", format: gnf },
    { key: "max_fee_gnf", label: "Frais maximum", format: gnf },
    { key: "passthrough_to_recipient", label: "Répercuté au bénéficiaire", format: bool },
  ];

  const pick = (specs: DiffSpec[], base: Row | undefined) =>
    Object.fromEntries(specs.filter((s) => s.key in draft).map((s) => [s.key, valueOf(s.key, base)]));

  const starterDiff = diffRecords(starterBase, pick(STARTER_SPECS, starterBase), STARTER_SPECS);
  const payoutDiff = diffRecords(payoutBase, pick(PAYOUT_SPECS, payoutBase), PAYOUT_SPECS);
  const msDiff = diffRecords(msBase, pick(MS_SPECS, msBase), MS_SPECS);
  const pfDiff = diffRecords(pfBase, pick(PF_SPECS, pfBase), PF_SPECS);

  return (
    <div className="space-y-4">
      {/* Feature flags */}
      <Card className="p-4 space-y-2">
        <div className="flex items-center justify-between">
          <h3 className="font-bold text-sm">Activation par étapes</h3>
          <Badge variant="secondary">
            {FINANCE_FLAGS.filter((f) => flagOn(f.key)).length}/{FINANCE_FLAGS.length} actifs
          </Badge>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Aucun interrupteur global : chaque capacité financière s'active séparément, avec motif et journal d'audit.
        </p>
        <div className="divide-y">
          {FINANCE_FLAGS.map((f) => (
            <div key={f.key} className="flex items-center justify-between py-2 gap-3">
              <div className="min-w-0">
                <p className="text-sm">{f.label}</p>
                <p className="text-[11px] text-muted-foreground font-mono break-all">{f.key} · {f.hint}</p>
              </div>
              <Switch
                checked={flagOn(f.key)}
                disabled={!isGodAdmin || saving}
                onCheckedChange={(v) => setPendingFlag({ key: f.key, label: f.label, value: v })}
              />
            </div>
          ))}
        </div>
      </Card>

      {/* Starter bonus */}
      <Card className="p-4 space-y-3">
        <h3 className="font-bold text-sm">Bonus de démarrage chauffeur (restreint)</h3>
        <p className="text-[11px] text-muted-foreground">
          Octroyé une seule fois, après vérification d'identité/véhicule. Non retirable, non transférable,
          jamais utilisable pour le principal marchandise. Les modifications ne concernent que les futurs octrois ;
          les bonus déjà accordés restent inchangés.
        </p>
        {baseBanner("starter", starterBase, starterRows)}
        <div className="grid sm:grid-cols-3 gap-3 items-end">
          {numField("amount_gnf", "Montant (GNF)", starterBase, !isGodAdmin)}
          <div className="flex items-center gap-2 h-10">
            <Switch
              checked={Boolean(valueOf("enabled", starterBase))}
              disabled={!isGodAdmin}
              onCheckedChange={(v) => setVal("enabled", v)}
            />
            <span className="text-xs">Programme actif</span>
          </div>
          {effField("starter", !isGodAdmin)}
        </div>
        {scheduledLine(starterRows, (r) => `${gnf(r.amount_gnf)} · ${bool(r.enabled)}`)}
        <div className="flex items-center gap-2">
          <Button size="sm" disabled={!isGodAdmin || starterDiff.length === 0} onClick={() => setConfirm("starter")}>
            Vérifier et programmer
          </Button>
          <span className="text-[11px] text-muted-foreground">
            {starterDiff.length === 0 ? "Aucune modification" : `${starterDiff.length} champ(s) modifié(s)`}
          </span>
        </div>
        {historyBlock("starter", starterRows, (r) => `${gnf(r.amount_gnf)} · ${bool(r.enabled)}`)}
      </Card>

      {/* Payout policy */}
      <Card className="p-4 space-y-3">
        <h3 className="font-bold text-sm">Politique de retrait chauffeur (documentée, inactive)</h3>
        {baseBanner("payout", payoutBase, payoutRows)}
        <div className="grid sm:grid-cols-3 gap-3">
          {numField("min_request_gnf", "Minimum (GNF)", payoutBase, !isGodAdmin)}
          {numField("max_request_gnf", "Maximum (GNF)", payoutBase, !isGodAdmin)}
          {numField("daily_limit_gnf", "Plafond quotidien (GNF)", payoutBase, !isGodAdmin)}
          {numField("cancel_window_seconds", "Fenêtre d'annulation (s)", payoutBase, !isGodAdmin)}
          {numField("processing_estimate_min_minutes", "Délai min (min)", payoutBase, !isGodAdmin)}
          {numField("processing_estimate_max_minutes", "Délai max (min)", payoutBase, !isGodAdmin)}
          {effField("payout", !isGodAdmin)}
        </div>
        <div className="flex items-center gap-2">
          <Switch
            checked={Boolean(valueOf("provider_fee_passthrough", payoutBase))}
            disabled={!isGodAdmin}
            onCheckedChange={(v) => setVal("provider_fee_passthrough", v)}
          />
          <span className="text-xs">Frais opérateur répercutés au chauffeur</span>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Une seule demande en attente · numéro Orange Money enregistré uniquement · fonds restreints non retirables ·
          blocage en cas de litige ou de gel. Invariants serveur, non modifiables ici.
        </p>
        {scheduledLine(payoutRows, (r) => `${gnf(r.min_request_gnf)} → ${gnf(r.max_request_gnf)}`)}
        <div className="flex items-center gap-2">
          <Button size="sm" disabled={!isGodAdmin || payoutDiff.length === 0} onClick={() => setConfirm("payout")}>
            Vérifier et programmer
          </Button>
          <span className="text-[11px] text-muted-foreground">
            {payoutDiff.length === 0 ? "Aucune modification" : `${payoutDiff.length} champ(s) modifié(s)`}
          </span>
        </div>
        {historyBlock("payout", payoutRows, (r) =>
          `${gnf(r.min_request_gnf)} → ${gnf(r.max_request_gnf)} · plafond ${gnf(r.daily_limit_gnf)}`)}
      </Card>

      {/* Merchant settlement */}
      <Card className="p-4 space-y-3">
        <h3 className="font-bold text-sm">Règlement marchand (comptes fournisseurs)</h3>
        <div className="flex items-center gap-2 flex-wrap">
          <Badge variant={activeOf(settlementRows)?.configured ? "secondary" : "destructive"}>
            {activeOf(settlementRows)?.configured
              ? "Infrastructure configurée"
              : "Non configuré — les commandes espèces marchand restent bloquées"}
          </Badge>
          <span className="text-[11px] text-muted-foreground">
            Réconciliation par preuve obligatoire avant tout débit (invariant serveur, non modifiable).
          </span>
        </div>
        {baseBanner("ms", msBase, settlementRows)}
        <div className="flex items-center gap-2">
          <Switch
            checked={Boolean(valueOf("configured", msBase))}
            disabled={!isGodAdmin}
            onCheckedChange={(v) => setVal("configured", v)}
          />
          <span className="text-xs">Infrastructure de règlement configurée</span>
        </div>
        <div className="grid sm:grid-cols-3 gap-3">
          <div>
            <Label className="text-xs">Cadence</Label>
            <select
              className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
              disabled={!isGodAdmin}
              value={String(valueOf("cadence", msBase) ?? "")}
              onChange={(e) => setVal("cadence", e.target.value === "" ? null : e.target.value)}
            >
              {CADENCES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          {numField("min_settlement_gnf", "Règlement minimum (GNF)", msBase, !isGodAdmin, "Vide = non configuré (jamais 0)")}
          {numField("max_settlement_gnf", "Règlement maximum (GNF)", msBase, !isGodAdmin, "Vide = aucun plafond configuré")}
          {numField("fee_bps", "Frais (bps)", msBase, !isGodAdmin, "Vide = non configuré")}
          {numField("fee_fixed_gnf", "Frais fixes (GNF)", msBase, !isGodAdmin, "Vide = non configuré")}
          {effField("ms", !isGodAdmin)}
        </div>
        <div className="flex items-center gap-2">
          <Switch
            checked={Boolean(valueOf("fee_passthrough", msBase))}
            disabled={!isGodAdmin}
            onCheckedChange={(v) => setVal("fee_passthrough", v)}
          />
          <span className="text-xs">Frais répercutés au marchand</span>
        </div>
        {scheduledLine(settlementRows, (r) => `${bool(r.configured)} · ${cadenceLabel(r.cadence)}`)}
        <div className="flex items-center gap-2">
          <Button size="sm" disabled={!isGodAdmin || msDiff.length === 0} onClick={() => setConfirm("ms")}>
            Vérifier et programmer
          </Button>
          <span className="text-[11px] text-muted-foreground">
            {msDiff.length === 0 ? "Aucune modification" : `${msDiff.length} champ(s) modifié(s)`}
          </span>
        </div>
        {historyBlock("ms", settlementRows, (r) =>
          `${bool(r.configured)} · ${cadenceLabel(r.cadence)} · min ${gnf(r.min_settlement_gnf)}`)}
      </Card>

      {/* Provider fees + delegation */}
      <Card className="p-4 space-y-3">
        <div className="flex items-center justify-between gap-2">
          <h3 className="font-bold text-sm">Frais opérateur Orange Money</h3>
          <Badge variant={delegated ? "secondary" : "outline"} className="gap-1">
            <Lock className="w-3 h-3" />
            {delegated ? "Délégué au Finance Admin" : "God Admin uniquement"}
          </Badge>
        </div>
        {baseBanner("pf", pfBase, feeRows)}
        <div className="grid sm:grid-cols-3 gap-3">
          {numField("fee_bps", "Frais (bps)", pfBase, !canPf)}
          {numField("fee_fixed_gnf", "Frais fixes (GNF)", pfBase, !canPf)}
          {numField("min_fee_gnf", "Frais minimum (GNF)", pfBase, !canPf)}
          {numField("max_fee_gnf", "Frais maximum (GNF)", pfBase, !canPf)}
          {effField("pf", !canPf)}
        </div>
        <div className="flex items-center gap-2">
          <Switch
            checked={Boolean(valueOf("passthrough_to_recipient", pfBase))}
            disabled={!canPf}
            onCheckedChange={(v) => setVal("passthrough_to_recipient", v)}
          />
          <span className="text-xs">Frais répercutés au bénéficiaire</span>
        </div>
        <div className="flex items-center gap-2">
          <Switch
            checked={delegated}
            disabled={!isGodAdmin || saving}
            onCheckedChange={(v) =>
              run(() =>
                supabase.rpc("admin_set_finance_delegation", {
                  p_provider_fee_to_finance_admin: v,
                  p_note: v
                    ? "Délégation des frais opérateur activée depuis la console politique financière"
                    : "Délégation des frais opérateur retirée depuis la console politique financière",
                }).then((r) => ({ error: r.error })), "Délégation mise à jour")
            }
          />
          <span className="text-xs">Autoriser le Finance Admin à modifier les frais opérateur</span>
        </div>
        {scheduledLine(feeRows, (r) => `${bps(r.fee_bps)} + ${gnf(r.fee_fixed_gnf)}`)}
        <div className="flex items-center gap-2">
          <Button size="sm" disabled={!canPf || pfDiff.length === 0} onClick={() => setConfirm("pf")}>
            Vérifier et programmer
          </Button>
          <span className="text-[11px] text-muted-foreground">
            {pfDiff.length === 0 ? "Aucune modification" : `${pfDiff.length} champ(s) modifié(s)`}
          </span>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Les frais opérateur sont distincts de la commission chauffeur et des frais de transaction CHOPCHOP.
          Un Finance Admin délégué doit lui aussi fournir un motif et une date d'effet ; chaque écriture est auditée.
        </p>
        {historyBlock("pf", feeRows, (r) => `${bps(r.fee_bps)} + ${gnf(r.fee_fixed_gnf)}`)}
      </Card>

      {/* Confirmations */}
      <PolicyConfirmDialog
        open={confirm === "starter"} onOpenChange={(v) => !v && setConfirm(null)}
        title="Bonus de démarrage chauffeur"
        effectiveFrom={fmtDateTime(at("starter").toISOString())}
        diff={starterDiff} saving={saving}
        onConfirm={(reason) => run(() =>
          supabase.rpc("admin_set_starter_credit_policy", {
            p_amount_gnf: valueOf("amount_gnf", starterBase) as number,
            p_enabled: Boolean(valueOf("enabled", starterBase)),
            p_effective_from: at("starter").toISOString(),
            p_note: reason,
          }).then((r) => ({ error: r.error })), "Bonus de démarrage programmé")}
      />
      <PolicyConfirmDialog
        open={confirm === "payout"} onOpenChange={(v) => !v && setConfirm(null)}
        title="Politique de retrait chauffeur"
        effectiveFrom={fmtDateTime(at("payout").toISOString())}
        diff={payoutDiff} saving={saving}
        onConfirm={(reason) => run(() =>
          supabase.rpc("admin_set_payout_policy", {
            p_min_request_gnf: valueOf("min_request_gnf", payoutBase) as number,
            p_max_request_gnf: valueOf("max_request_gnf", payoutBase) as number,
            p_daily_limit_gnf: valueOf("daily_limit_gnf", payoutBase) as number,
            p_cancel_window_seconds: valueOf("cancel_window_seconds", payoutBase) as number,
            p_processing_estimate_min_minutes: valueOf("processing_estimate_min_minutes", payoutBase) as number,
            p_processing_estimate_max_minutes: valueOf("processing_estimate_max_minutes", payoutBase) as number,
            p_provider_fee_passthrough: Boolean(valueOf("provider_fee_passthrough", payoutBase)),
            p_effective_from: at("payout").toISOString(),
            p_note: reason,
          }).then((r) => ({ error: r.error })), "Politique de retrait programmée")}
      />
      <PolicyConfirmDialog
        open={confirm === "ms"} onOpenChange={(v) => !v && setConfirm(null)}
        title="Règlement marchand"
        effectiveFrom={fmtDateTime(at("ms").toISOString())}
        diff={msDiff} saving={saving}
        onConfirm={(reason) => run(() =>
          supabase.rpc("admin_set_merchant_settlement_policy", {
            p_configured: Boolean(valueOf("configured", msBase)),
            p_cadence: (valueOf("cadence", msBase) as string | null) ?? null,
            p_min_settlement_gnf: valueOf("min_settlement_gnf", msBase) as number | null,
            p_max_settlement_gnf: valueOf("max_settlement_gnf", msBase) as number | null,
            p_fee_bps: valueOf("fee_bps", msBase) as number | null,
            p_fee_fixed_gnf: valueOf("fee_fixed_gnf", msBase) as number | null,
            p_fee_passthrough: valueOf("fee_passthrough", msBase) as boolean | null,
            p_effective_from: at("ms").toISOString(),
            p_note: reason,
          }).then((r) => ({ error: r.error })), "Politique de règlement programmée")}
      />
      <PolicyConfirmDialog
        open={confirm === "pf"} onOpenChange={(v) => !v && setConfirm(null)}
        title="Frais opérateur Orange Money"
        effectiveFrom={fmtDateTime(at("pf").toISOString())}
        diff={pfDiff} saving={saving}
        onConfirm={(reason) => run(() =>
          supabase.rpc("admin_set_provider_fee_schedule", {
            p_provider: "orange_money",
            p_fee_bps: valueOf("fee_bps", pfBase) as number,
            p_fee_fixed_gnf: valueOf("fee_fixed_gnf", pfBase) as number,
            p_min_fee_gnf: valueOf("min_fee_gnf", pfBase) as number,
            p_max_fee_gnf: valueOf("max_fee_gnf", pfBase) as number,
            p_passthrough_to_recipient: Boolean(valueOf("passthrough_to_recipient", pfBase)),
            p_effective_from: at("pf").toISOString(),
            p_note: reason,
          }).then((r) => ({ error: r.error })), "Barème opérateur programmé")}
      />
      <FlagConfirmDialog
        pending={pendingFlag}
        currentEnabled={pendingFlag ? flagOn(pendingFlag.key) : false}
        saving={saving}
        onCancel={() => setPendingFlag(null)}
        onConfirm={(reason) => {
          const p = pendingFlag;
          if (!p) return;
          setPendingFlag(null);
          void run(() =>
            supabase.rpc("admin_set_feature_flag", { p_key: p.key, p_enabled: p.value, p_note: reason })
              .then((r) => ({ error: r.error })),
            `${p.label} — ${p.value ? "activé" : "désactivé"}`);
        }}
      />
    </div>
  );
}
