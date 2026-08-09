import { useCallback, useEffect, useState } from "react";
import { Loader2, Lock } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { useAuth } from "@/contexts/AuthContext";
import { fmtDateTime } from "@/lib/admin/financePolicy";

/** Financial flags whose activation is staged per the canonical operating policy. */
const FINANCE_FLAGS: { key: string; label: string; hint: string }[] = [
  { key: "om_topup_enabled", label: "Rechargement Orange Money", hint: "Étape 1 — actif au lancement" },
  { key: "chop_pay_enabled", label: "Chop Pay (solde visible)", hint: "Étape 2" },
  { key: "driver_balance_gate_enabled", label: "Blocage offres sur solde chauffeur", hint: "Étape 3" },
  { key: "driver_starter_credit_enabled", label: "Bonus de démarrage chauffeur", hint: "Étape 4" },
  { key: "chop_pay_checkout_enabled", label: "Paiement Chop Pay", hint: "Étape 5" },
  { key: "cash_order_funding_enabled", label: "Financement commandes espèces", hint: "Étape 6" },
  { key: "merchant_om_settlement_enabled", label: "Règlement marchand", hint: "Étape 7" },
  { key: "driver_cashout_enabled", label: "Retrait chauffeur", hint: "Étape 8" },
  { key: "chop_pay_p2p_enabled", label: "Transferts P2P", hint: "Hors périmètre lancement" },
  { key: "om_direct_checkout_enabled", label: "Paiement direct Orange Money", hint: "Archivé" },
];

interface Row { [k: string]: unknown }

export function FinanceControlsPanel({ isGodAdmin }: { isGodAdmin: boolean }) {
  const { roles } = useAuth();
  const isFinanceAdmin = roles.includes("finance_admin");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [flags, setFlags] = useState<{ key: string; enabled: boolean }[]>([]);
  const [starter, setStarter] = useState<Row | null>(null);
  const [payout, setPayout] = useState<Row | null>(null);
  const [settlement, setSettlement] = useState<Row | null>(null);
  const [providerFee, setProviderFee] = useState<Row | null>(null);
  const [delegated, setDelegated] = useState(false);
  const [draft, setDraft] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    const [f, sc, pp, ms, pf, del] = await Promise.all([
      supabase.from("feature_flags").select("key,enabled"),
      supabase.from("driver_starter_credit_policies").select("*").order("effective_from", { ascending: false }).limit(1),
      supabase.from("driver_payout_policies").select("*").order("effective_from", { ascending: false }).limit(1),
      supabase.from("merchant_settlement_policies").select("*").order("effective_from", { ascending: false }).limit(1),
      supabase.from("provider_fee_schedules").select("*").eq("provider", "orange_money").order("effective_from", { ascending: false }).limit(1),
      supabase.from("app_settings").select("value").eq("key", "finance_delegation").maybeSingle(),
    ]);
    setFlags((f.data ?? []) as { key: string; enabled: boolean }[]);
    setStarter((sc.data?.[0] ?? null) as Row | null);
    setPayout((pp.data?.[0] ?? null) as Row | null);
    setSettlement((ms.data?.[0] ?? null) as Row | null);
    setProviderFee((pf.data?.[0] ?? null) as Row | null);
    const v = del.data?.value as { provider_fee_to_finance_admin?: boolean } | null;
    setDelegated(Boolean(v?.provider_fee_to_finance_admin));
    setDraft({});
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const run = async (id: string, fn: () => Promise<{ error: { message: string } | null }>, okMsg: string) => {
    setBusy(id);
    const { error } = await fn();
    setBusy(null);
    if (error) { toast({ title: "Refusé par le serveur", description: error.message, variant: "destructive" }); return; }
    toast({ title: okMsg });
    void load();
  };

  const numDraft = (k: string, fallback: unknown) =>
    draft[k] !== undefined && draft[k] !== "" ? Number(draft[k]) : Number(fallback ?? 0);
  const field = (k: string, label: string, value: unknown, disabled: boolean) => (
    <div key={k}>
      <Label className="text-xs">{label}</Label>
      <Input
        type="number" min={0} disabled={disabled}
        value={draft[k] ?? String(value ?? "")}
        onChange={(e) => setDraft((p) => ({ ...p, [k]: e.target.value }))}
      />
    </div>
  );

  if (loading) return <Loader2 className="w-5 h-5 animate-spin" />;

  const flagOn = (k: string) => flags.find((x) => x.key === k)?.enabled ?? false;

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
          Aucun interrupteur global : chaque capacité financière s'active séparément et de façon auditée.
        </p>
        <div className="divide-y">
          {FINANCE_FLAGS.map((f) => (
            <div key={f.key} className="flex items-center justify-between py-2 gap-3">
              <div className="min-w-0">
                <p className="text-sm">{f.label}</p>
                <p className="text-[11px] text-muted-foreground font-mono">{f.key} · {f.hint}</p>
              </div>
              <Switch
                checked={flagOn(f.key)}
                disabled={!isGodAdmin || busy === f.key}
                onCheckedChange={(v) =>
                  run(f.key, () =>
                    supabase.rpc("admin_set_feature_flag", {
                      p_key: f.key, p_enabled: v, p_note: "Console politique financière",
                    }).then((r) => ({ error: r.error })),
                  `${f.label} — ${v ? "activé" : "désactivé"}`)
                }
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
          jamais utilisable pour le principal marchandise. Les modifications ne concernent que les futurs chauffeurs.
        </p>
        <div className="grid sm:grid-cols-3 gap-3 items-end">
          {field("starter_amount", "Montant (GNF)", starter?.amount_gnf, !isGodAdmin)}
          <div className="flex items-center gap-2 h-10">
            <Switch
              checked={Boolean(starter?.enabled)}
              disabled={!isGodAdmin || busy === "starter_toggle"}
              onCheckedChange={(v) =>
                run("starter_toggle", () =>
                  supabase.rpc("admin_set_starter_credit_policy", {
                    p_amount_gnf: Number(starter?.amount_gnf ?? 25000),
                    p_enabled: v,
                    p_note: "Console politique financière",
                  }).then((r) => ({ error: r.error })), "Bonus de démarrage mis à jour")
              }
            />
            <span className="text-xs">Programme actif</span>
          </div>
          <Button
            size="sm" disabled={!isGodAdmin || busy === "starter"}
            onClick={() =>
              run("starter", () =>
                supabase.rpc("admin_set_starter_credit_policy", {
                  p_amount_gnf: numDraft("starter_amount", starter?.amount_gnf ?? 25000),
                  p_enabled: Boolean(starter?.enabled),
                  p_note: "Console politique financière",
                }).then((r) => ({ error: r.error })), "Bonus de démarrage programmé")
            }
          >
            Programmer
          </Button>
        </div>
        {starter && (
          <p className="text-[11px] text-muted-foreground">
            En vigueur depuis {fmtDateTime(String(starter.effective_from))}
          </p>
        )}
      </Card>

      {/* Payout policy */}
      <Card className="p-4 space-y-3">
        <h3 className="font-bold text-sm">Politique de retrait chauffeur (documentée, inactive)</h3>
        <div className="grid sm:grid-cols-3 gap-3">
          {field("payout_min", "Minimum (GNF)", payout?.min_request_gnf, !isGodAdmin)}
          {field("payout_max", "Maximum (GNF)", payout?.max_request_gnf, !isGodAdmin)}
          {field("payout_daily", "Plafond quotidien (GNF)", payout?.daily_limit_gnf, !isGodAdmin)}
          {field("payout_cancel", "Fenêtre d'annulation (s)", payout?.cancel_window_seconds, !isGodAdmin)}
          {field("payout_min_min", "Délai min (min)", payout?.processing_estimate_min_minutes, !isGodAdmin)}
          {field("payout_max_min", "Délai max (min)", payout?.processing_estimate_max_minutes, !isGodAdmin)}
        </div>
        <p className="text-[11px] text-muted-foreground">
          Une seule demande en attente · numéro Orange Money enregistré uniquement · fonds restreints non retirables ·
          frais opérateur répercutés · blocage en cas de litige ou de gel. Invariants serveur, non modifiables ici.
        </p>
        <Button
          size="sm" disabled={!isGodAdmin || busy === "payout"}
          onClick={() =>
            run("payout", () =>
              supabase.rpc("admin_set_payout_policy", {
                p_min_request_gnf: numDraft("payout_min", payout?.min_request_gnf),
                p_max_request_gnf: numDraft("payout_max", payout?.max_request_gnf),
                p_daily_limit_gnf: numDraft("payout_daily", payout?.daily_limit_gnf),
                p_cancel_window_seconds: numDraft("payout_cancel", payout?.cancel_window_seconds),
                p_processing_estimate_min_minutes: numDraft("payout_min_min", payout?.processing_estimate_min_minutes),
                p_processing_estimate_max_minutes: numDraft("payout_max_min", payout?.processing_estimate_max_minutes),
                p_provider_fee_passthrough: Boolean(payout?.provider_fee_passthrough ?? true),
                p_note: "Console politique financière",
              }).then((r) => ({ error: r.error })), "Politique de retrait programmée")
          }
        >
          Programmer
        </Button>
      </Card>

      {/* Merchant settlement */}
      <Card className="p-4 space-y-3">
        <h3 className="font-bold text-sm">Règlement marchand (comptes fournisseurs)</h3>
        <div className="grid sm:grid-cols-3 gap-3">
          {field("ms_min", "Règlement minimum (GNF)", settlement?.min_settlement_gnf, !isGodAdmin)}
          {field("ms_max", "Règlement maximum (GNF)", settlement?.max_settlement_gnf, !isGodAdmin)}
          {field("ms_fee", "Frais (bps)", settlement?.fee_bps, !isGodAdmin)}
        </div>
        <div className="flex items-center gap-2">
          <Badge variant={settlement?.configured ? "secondary" : "destructive"}>
            {settlement?.configured ? "Infrastructure configurée" : "Non configuré — bloque les commandes espèces"}
          </Badge>
          <span className="text-[11px] text-muted-foreground">
            Réconciliation par preuve obligatoire avant tout débit.
          </span>
        </div>
        <Button
          size="sm" disabled={!isGodAdmin || busy === "ms"}
          onClick={() =>
            run("ms", () =>
              supabase.rpc("admin_set_merchant_settlement_policy", {
                p_configured: Boolean(settlement?.configured),
                p_min_settlement_gnf: numDraft("ms_min", settlement?.min_settlement_gnf),
                p_max_settlement_gnf: numDraft("ms_max", settlement?.max_settlement_gnf),
                p_fee_bps: numDraft("ms_fee", settlement?.fee_bps),
                p_fee_fixed_gnf: Number(settlement?.fee_fixed_gnf ?? 0),
                p_fee_passthrough: Boolean(settlement?.fee_passthrough ?? true),
                p_cadence: String(settlement?.cadence ?? "manual"),
                p_note: "Console politique financière",
              }).then((r) => ({ error: r.error })), "Politique de règlement programmée")
          }
        >
          Programmer
        </Button>
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
        <div className="grid sm:grid-cols-3 gap-3">
          {field("pf_bps", "Frais (bps)", providerFee?.fee_bps, !(isGodAdmin || (isFinanceAdmin && delegated)))}
          {field("pf_fixed", "Frais fixes (GNF)", providerFee?.fee_fixed_gnf, !(isGodAdmin || (isFinanceAdmin && delegated)))}
          {field("pf_max", "Frais max (GNF)", providerFee?.max_fee_gnf, !(isGodAdmin || (isFinanceAdmin && delegated)))}
        </div>
        <div className="flex items-center gap-2">
          <Switch
            checked={delegated}
            disabled={!isGodAdmin || busy === "deleg"}
            onCheckedChange={(v) =>
              run("deleg", () =>
                supabase.rpc("admin_set_finance_delegation", {
                  p_provider_fee_to_finance_admin: v,
                  p_note: "Console politique financière",
                }).then((r) => ({ error: r.error })), "Délégation mise à jour")
            }
          />
          <span className="text-xs">Autoriser le Finance Admin à modifier les frais opérateur</span>
        </div>
        <Button
          size="sm"
          disabled={!(isGodAdmin || (isFinanceAdmin && delegated)) || busy === "pf"}
          onClick={() =>
            run("pf", () =>
              supabase.rpc("admin_set_provider_fee_schedule", {
                p_provider: "orange_money",
                p_fee_bps: numDraft("pf_bps", providerFee?.fee_bps),
                p_fee_fixed_gnf: numDraft("pf_fixed", providerFee?.fee_fixed_gnf),
                p_max_fee_gnf: numDraft("pf_max", providerFee?.max_fee_gnf),
                p_min_fee_gnf: Number(providerFee?.min_fee_gnf ?? 0),
                p_passthrough_to_recipient: Boolean(providerFee?.passthrough_to_recipient ?? true),
                p_note: "Console politique financière",
              }).then((r) => ({ error: r.error })), "Barème opérateur programmé")
          }
        >
          Programmer
        </Button>
        <p className="text-[11px] text-muted-foreground">
          Les frais opérateur sont distincts de la commission chauffeur et des frais de transaction CHOPCHOP.
        </p>
      </Card>
    </div>
  );
}
