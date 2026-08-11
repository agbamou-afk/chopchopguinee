import { useState } from "react";
import { Loader2, RefreshCw, ShieldAlert, ChevronRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { ModulePage } from "@/components/admin/ModulePage";
import { formatGNF } from "@/lib/format";
import {
  useTreasury, fetchTreasuryDrilldown,
  type TreasuryException, type TreasuryDrilldownRow, type TreasuryOverview,
} from "@/lib/finance/treasury";

const SEVERITY_TONE: Record<string, string> = {
  critical: "bg-destructive/15 text-destructive",
  high: "bg-warning/15 text-warning",
  warning: "bg-secondary/40 text-foreground",
};

const CODE_LABEL: Record<string, string> = {
  TREASURY_SHORTFALL: "Déficit de couverture trésorerie",
  TREASURY_SURPLUS: "Excédent de couverture trésorerie",
  WALLET_LEDGER_MISMATCH: "Écart soldes ↔ grand livre",
  MASTER_WALLET_DEFICIT: "Déficit wallet maître (DEF-FIN-001)",
  MERCHANT_PAYABLE_MISMATCH: "Écart dettes marchands ↔ grand livre",
  CLAIM_RESERVE_MISMATCH: "Écart réserves litiges ↔ grand livre",
  PROVIDER_CLEARING_MISMATCH: "Écart compensation opérateur",
  INBOUND_OM_UNRECONCILED: "Entrées Orange Money non rapprochées",
  INBOUND_OM_UNMATCHED_EVENT: "Événements opérateur non appariés",
  OUTBOUND_PAYOUT_UNRECONCILED: "Sorties sans preuve rapprochée",
  LEDGER_GLOBAL_IMBALANCE: "Grand livre global déséquilibré",
  LEDGER_JOURNAL_IMBALANCE: "Écriture déséquilibrée",
};

function Metric({ label, value, hint, tone }: { label: string; value: string; hint?: string; tone?: string }) {
  return (
    <div className="rounded-lg border border-border/60 p-3">
      <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`text-[15px] font-semibold tabular-nums mt-1 ${tone ?? ""}`}>{value}</p>
      {hint && <p className="text-[11px] text-muted-foreground mt-1">{hint}</p>}
    </div>
  );
}

function Section({ title, note, children }: { title: string; note?: string; children: React.ReactNode }) {
  return (
    <Card className="p-4 space-y-3">
      <div>
        <h2 className="text-[13px] font-semibold">{title}</h2>
        {note && <p className="text-[11px] text-muted-foreground mt-0.5">{note}</p>}
      </div>
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">{children}</div>
    </Card>
  );
}

function OverviewTab({ o }: { o: TreasuryOverview }) {
  const delta = o.treasury_coverage_delta_gnf;
  return (
    <div className="space-y-3">
      <Section
        title="Actifs vérifiés"
        note="Uniquement l'argent confirmé par l'opérateur : entrées créditées moins sorties réglées avec preuve."
      >
        <Metric label="Actifs vérifiés" value={formatGNF(o.verified_assets_gnf)} />
        <Metric label="Entrées OM créditées" value={formatGNF(o.om_inbound_credited_gnf)} />
        <Metric label="Sorties OM réglées" value={formatGNF(o.om_outbound_settled_gnf)} />
        <Metric label="Compensation opérateur (grand livre)" value={formatGNF(o.provider_clearing_ledger_gnf)} />
      </Section>

      <Section title="Obligations" note="Ce que la plateforme doit, par catégorie de bénéficiaire.">
        <Metric label="Clients" value={formatGNF(o.total_customer_liability_gnf)} />
        <Metric label="Chauffeurs" value={formatGNF(o.total_driver_liability_gnf)} />
        <Metric label="Marchands" value={formatGNF(o.total_merchant_liability_gnf)} />
        <Metric label="Dettes marchands ouvertes" value={formatGNF(o.merchant_payable_outstanding_gnf)} />
        <Metric label="Fonds bloqués / restreints" value={formatGNF(o.restricted_or_held_liability_gnf)} />
        <Metric
          label="Crédits promo (financés plateforme)"
          value={formatGNF(o.promotional_credit_liability_gnf)}
          hint="Exclus des obligations couvertes en cash"
        />
        <Metric
          label="Réservé pour versement"
          value={formatGNF(o.merchant_settlement_reserved_gnf)}
          hint={`${o.merchant_settlement_reserved_count} réservation(s) — aucun débit`}
        />
        <Metric
          label="Wallet maître"
          value={formatGNF(o.master_wallet_balance_gnf)}
          tone={o.master_wallet_balance_gnf < 0 ? "text-destructive" : undefined}
          hint="Gelé par politique (DEF-FIN-001)"
        />
      </Section>

      <Section
        title="Couverture"
        note="Écart signalé tel quel. Aucun ajustement, aucune écriture d'équilibrage n'est produite ici."
      >
        <Metric label="Obligations couvertes en cash" value={formatGNF(o.covered_obligations_gnf)} />
        <Metric
          label="Écart de couverture"
          value={formatGNF(delta)}
          tone={delta < 0 ? "text-destructive" : delta > 0 ? "text-warning" : undefined}
          hint={delta === 0 ? "Couvert" : delta < 0 ? "Déficit — exception ouverte" : "Excédent — exception ouverte"}
        />
      </Section>

      <Section title="Litiges (Envoyer)" note="Exposition déclarée et obligation reconnue, séparées des paiements effectués.">
        <Metric label="Obligation reconnue" value={formatGNF(o.recognized_claims_obligation_gnf)} />
        <Metric
          label="Exposition ouverte (valeur déclarée)"
          value={formatGNF(o.open_claims_exposure_gnf)}
          hint={`${o.open_claims_count} dossier(s) ouvert(s)`}
        />
        <Metric label="Litiges payés" value={formatGNF(o.claims_paid_gnf)} />
        <Metric label="Litiges libérés" value={formatGNF(o.claims_released_gnf)} />
      </Section>

      <Section title="Créances" note="Frais d'annulation dus par les clients. Ce ne sont ni du cash ni du revenu capturé.">
        <Metric
          label="Créances ouvertes"
          value={formatGNF(o.cancellation_debt_receivable_gnf)}
          hint={`${o.cancellation_debt_open_count} dossier(s)`}
        />
        <Metric label="Recouvré" value={formatGNF(o.cancellation_debt_collected_gnf)} />
        <Metric label="Annulé / exonéré" value={formatGNF(o.cancellation_debt_waived_gnf)} />
      </Section>

      <Section title="Revenu capturé" note="Uniquement les comptes de revenu du grand livre. Aucune projection.">
        <Metric label="Total capturé" value={formatGNF(o.captured_revenue_gnf)} />
        <Metric label="Commission course" value={formatGNF(o.captured_revenue_breakdown.ride_commission_gnf)} />
        <Metric label="Frais de transaction" value={formatGNF(o.captured_revenue_breakdown.transaction_fee_gnf)} />
        <Metric label="Frais d'annulation" value={formatGNF(o.captured_revenue_breakdown.cancellation_fee_gnf)} />
        <Metric label="Caution récupérée" value={formatGNF(o.captured_revenue_breakdown.recovered_collateral_gnf)} />
      </Section>

      <Section title="Posture opérationnelle" note="File d'attente entrante et sortante, sans effet sur les soldes.">
        <Metric
          label="Entrées OM à rapprocher"
          value={formatGNF(o.inbound_om_unreconciled_gnf)}
          hint={`${o.inbound_om_unreconciled_count} demande(s)`}
        />
        <Metric label="Entrées OM en attente client" value={formatGNF(o.inbound_om_pending_gnf)} />
        <Metric
          label="Événements opérateur non appariés"
          value={formatGNF(o.inbound_om_unmatched_events_gnf)}
          hint={`${o.inbound_om_unmatched_events_count} événement(s)`}
        />
        <Metric
          label="Sorties sans preuve rapprochée"
          value={formatGNF(o.outbound_payout_unreconciled_gnf)}
          hint={`${o.outbound_payout_unreconciled_count} preuve(s)`}
        />
        <Metric label="Écritures au grand livre" value={String(o.ledger_posting_count)} />
        <Metric
          label="Somme globale du grand livre"
          value={formatGNF(o.ledger_global_sum_gnf)}
          tone={o.ledger_global_sum_gnf !== 0 ? "text-destructive" : undefined}
          hint={o.ledger_global_sum_gnf === 0 ? "Équilibré" : "Déséquilibré — exception ouverte"}
        />
      </Section>
    </div>
  );
}

function ExceptionsTab({ items }: { items: TreasuryException[] }) {
  const [open, setOpen] = useState<TreasuryException | null>(null);
  const [rows, setRows] = useState<TreasuryDrilldownRow[]>([]);
  const [busy, setBusy] = useState(false);

  const drill = async (e: TreasuryException) => {
    setOpen(e); setBusy(true); setRows([]);
    setRows(await fetchTreasuryDrilldown(e.code, 100));
    setBusy(false);
  };

  if (items.length === 0) {
    return (
      <Card className="p-8 text-center border-dashed">
        <p className="text-sm text-muted-foreground">
          Aucune exception de trésorerie. Chaque mesure correspond à sa source autoritaire.
        </p>
      </Card>
    );
  }

  return (
    <>
      <div className="space-y-2">
        {items.map((e, i) => (
          <Card key={`${e.code}-${i}`} className="p-3">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <span className={`text-[11px] px-2 py-0.5 rounded-full ${SEVERITY_TONE[e.severity] ?? "bg-muted"}`}>
                    {e.severity}
                  </span>
                  <span className="text-[13px] font-semibold">{CODE_LABEL[e.code] ?? e.code}</span>
                  <span className="text-[11px] text-muted-foreground font-mono">{e.code}</span>
                </div>
                <p className="text-[12px] text-muted-foreground mt-1">{e.detail}</p>
                <p className="text-[11px] text-muted-foreground mt-1">
                  {e.source_module}
                  {e.account_code ? ` · ${e.account_code}` : ""} · {e.entity_count} enregistrement(s) · {e.state}
                </p>
              </div>
              <div className="text-right shrink-0">
                <p className="text-[14px] font-semibold tabular-nums">{formatGNF(e.amount_gnf)}</p>
                <Button size="sm" variant="ghost" className="mt-1 h-7 px-2" onClick={() => void drill(e)}>
                  Détail <ChevronRight className="h-3.5 w-3.5 ml-1" />
                </Button>
              </div>
            </div>
          </Card>
        ))}
      </div>

      <Dialog open={!!open} onOpenChange={(v) => !v && setOpen(null)}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>{open ? (CODE_LABEL[open.code] ?? open.code) : ""}</DialogTitle>
            <DialogDescription>
              Enregistrements sources renvoyés par le serveur. Aucun calcul côté client.
            </DialogDescription>
          </DialogHeader>
          {busy ? (
            <div className="py-10 flex justify-center"><Loader2 className="h-5 w-5 animate-spin" /></div>
          ) : rows.length === 0 ? (
            <p className="text-sm text-muted-foreground py-6 text-center">Aucun enregistrement source à afficher.</p>
          ) : (
            <div className="max-h-[60vh] overflow-auto">
              <table className="w-full text-[12px]">
                <thead className="text-muted-foreground">
                  <tr className="text-left">
                    <th className="py-1 pr-2">Référence</th>
                    <th className="py-1 pr-2">Libellé</th>
                    <th className="py-1 pr-2 text-right">Montant</th>
                    <th className="py-1 pr-2">État</th>
                    <th className="py-1 pr-2">Module</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r, i) => (
                    <tr key={`${r.ref}-${i}`} className="border-t border-border/50">
                      <td className="py-1 pr-2 font-mono break-all">{r.ref}</td>
                      <td className="py-1 pr-2">{r.label}</td>
                      <td className="py-1 pr-2 text-right tabular-nums">{formatGNF(r.amount_gnf)}</td>
                      <td className="py-1 pr-2">{r.state}</td>
                      <td className="py-1 pr-2">{r.source_module}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}

/**
 * Slice 12 — Treasury & Finance operations console.
 *
 * Every figure is produced by `finance_treasury_overview` /
 * `finance_treasury_exceptions` / `finance_treasury_drilldown`. There is no
 * client-side arithmetic, no inferred adjustment and no balancing plug: an
 * unexplained difference is always shown as a named, quantified exception.
 */
export default function TreasuryAdmin() {
  const { overview, exceptions, error, loading, refresh } = useTreasury();
  const critical = exceptions.filter((e) => e.severity === "critical").length;

  return (
    <ModulePage
      module="wallet"
      title="Trésorerie & opérations financières"
      subtitle="Vue consolidée issue du grand livre, des soldes et des preuves opérateur — jamais reconstruite côté client."
      actions={
        <Button size="sm" variant="outline" onClick={() => void refresh()} disabled={loading}>
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
          <span className="ml-2">Actualiser</span>
        </Button>
      }
    >
      {loading && !overview ? (
        <Card className="p-10 flex justify-center"><Loader2 className="h-5 w-5 animate-spin" /></Card>
      ) : error || !overview ? (
        <Card className="p-8 text-center border-dashed space-y-2">
          <ShieldAlert className="h-5 w-5 mx-auto text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            {error ?? "Trésorerie indisponible."} Cette vue est réservée aux rôles god_admin et finance_admin.
          </p>
        </Card>
      ) : (
        <Tabs defaultValue="overview">
          <TabsList>
            <TabsTrigger value="overview">Vue d'ensemble</TabsTrigger>
            <TabsTrigger value="exceptions">
              Exceptions ({exceptions.length}{critical > 0 ? ` · ${critical} critiques` : ""})
            </TabsTrigger>
          </TabsList>
          <TabsContent value="overview" className="mt-3">
            <OverviewTab o={overview} />
          </TabsContent>
          <TabsContent value="exceptions" className="mt-3">
            <ExceptionsTab items={exceptions} />
          </TabsContent>
        </Tabs>
      )}
      {overview && (
        <p className="text-[11px] text-muted-foreground text-center">
          Généré le {new Date(overview.generated_at).toLocaleString("fr-FR")} · source : serveur autoritaire
        </p>
      )}
    </ModulePage>
  );
}
