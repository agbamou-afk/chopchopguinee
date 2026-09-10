import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle, ArrowDownToLine, ArrowUpFromLine, Landmark, RefreshCw, Receipt,
  Scale, Snowflake, Wallet,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import {
  FINANCE_DENIED_MESSAGE, OPS_ESCALATION, SEVERITY_CLASS, SEVERITY_LABEL,
  fetchFinanceOverview, formatGnf, modeLabel, relativeAge,
  type FinanceOverview, type FinanceSnapshot,
} from "@/lib/admin/financeCommandCenter";

const REFRESH_MS = 60_000;

const QUEUES: {
  key: keyof FinanceSnapshot; label: string; href: string; hint: string; icon: typeof Wallet;
}[] = [
  { key: "topups_pending", label: "Recharges à vérifier", href: "/admin/wallet/reconciliation",
    hint: "Aucun crédit sans preuve opérateur", icon: ArrowDownToLine },
  { key: "provider_events_open", label: "Événements opérateur ouverts", href: "/admin/wallet/reconciliation",
    hint: "Rapprochement entrant", icon: Scale },
  { key: "cashouts_pending", label: "Retraits chauffeurs", href: "/admin/wallet/driver-cashouts",
    hint: "Confirmation à quatre yeux", icon: ArrowUpFromLine },
  { key: "settlements_pending", label: "Règlements marchands", href: "/admin/wallet/payouts",
    hint: "Confirmation à quatre yeux", icon: Receipt },
  { key: "payouts_open", label: "Versements sortants ouverts", href: "/admin/wallet/payouts",
    hint: "Preuve opérateur exigée", icon: ArrowUpFromLine },
  { key: "refunds_pending", label: "Remboursements", href: "/admin/payments",
    hint: "Décision tracée, jamais automatique", icon: Wallet },
  { key: "intents_review", label: "Paiements en revue", href: "/admin/payments",
    hint: "Vérification opérateur", icon: AlertTriangle },
  { key: "wallets_frozen", label: "Portefeuilles gelés", href: "/admin/wallet",
    hint: "Gel gouvernance — lecture", icon: Snowflake },
];

export default function FinanceCommandCenter() {
  const { role } = useAdminAuth();
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<FinanceOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [denied, setDenied] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const res = await fetchFinanceOverview();
    if (res.ok) { setData(res.data); setError(null); setDenied(false); }
    else { setData(null); setError(res.error); setDenied(res.denied); }
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
    const id = window.setInterval(() => { if (!document.hidden) load(); }, REFRESH_MS);
    return () => window.clearInterval(id);
  }, [load]);

  const snapshot = data?.snapshot;

  return (
    <ModulePage
      module="payments"
      title="Centre finance"
      subtitle="Files financières réelles, issues du modèle de lecture serveur. Aucun mouvement automatique, aucune estimation."
      actions={
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCw className={`w-4 h-4 mr-1 ${loading ? "animate-spin" : ""}`} />
          Actualiser
        </Button>
      }
    >
      {error && (
        <Card className="p-4 border-destructive/40 bg-destructive/5">
          <p className="text-sm font-medium text-destructive">
            {denied ? FINANCE_DENIED_MESSAGE : "Indisponible"}
          </p>
          <p className="text-[11px] text-muted-foreground mt-1">{error}</p>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {QUEUES.map((q) => {
          const Icon = q.icon;
          const value = snapshot ? snapshot[q.key] : null;
          return (
            <Link key={q.key} to={q.href}>
              <Card className="p-4 h-full hover:border-primary/50 transition-colors">
                <Icon className="w-4 h-4 text-muted-foreground" />
                <p className="text-2xl font-semibold mt-3">
                  {value === null || value === undefined ? "Indisponible" : value}
                </p>
                <p className="text-sm font-medium">{q.label}</p>
                <p className="text-[11px] text-muted-foreground mt-1">
                  {value === 0 ? "0 élément — lecture réussie" : q.hint}
                </p>
              </Card>
            </Link>
          );
        })}
      </div>

      <Card className="p-4">
        <div className="flex items-center justify-between gap-3 mb-3">
          <div className="flex items-center gap-2">
            <Landmark className="w-4 h-4 text-muted-foreground" />
            <div>
              <p className="text-sm font-medium">Exceptions de trésorerie</p>
              <p className="text-[11px] text-muted-foreground">
                Écarts nommés et chiffrés — jamais compensés automatiquement.
              </p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-2xl font-semibold">
              {data ? data.exceptions_total : "Indisponible"}
            </p>
            <Link to="/admin/treasury" className="text-[11px] text-primary underline">
              Ouvrir la trésorerie
            </Link>
          </div>
        </div>
        <div className="space-y-2">
          {data?.exceptions.length === 0 && (
            <p className="text-[11px] text-muted-foreground">0 exception — lecture réussie.</p>
          )}
          {data?.exceptions.map((e) => (
            <div key={`${e.code}-${e.account_code ?? ""}`} className="flex items-start justify-between gap-3 border-t pt-2">
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-mono text-[11px]">{e.code}</span>
                  <Badge variant="outline" className={`text-[10px] ${SEVERITY_CLASS[e.severity] ?? ""}`}>
                    {SEVERITY_LABEL[e.severity] ?? e.severity}
                  </Badge>
                </div>
                <p className="text-[11px] text-muted-foreground mt-0.5">{e.detail}</p>
              </div>
              <p className="text-sm font-semibold whitespace-nowrap">{formatGnf(e.amount_gnf)}</p>
            </div>
          ))}
        </div>
      </Card>

      <Card className="p-4">
        <p className="text-sm font-medium mb-2">File d'attention financière</p>
        {!data && <p className="text-[11px] text-muted-foreground">Indisponible.</p>}
        {data?.attention.length === 0 && (
          <p className="text-[11px] text-muted-foreground">0 élément — lecture réussie.</p>
        )}
        <div className="space-y-2">
          {data?.attention.map((a) => (
            <Link
              key={`${a.kind}-${a.reference}`}
              to={a.href}
              className="flex items-start justify-between gap-3 border-t pt-2 hover:bg-muted/40 rounded-sm px-1"
            >
              <div>
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium">{a.label}</span>
                  <Badge variant="outline" className={`text-[10px] ${SEVERITY_CLASS[a.severity] ?? ""}`}>
                    {SEVERITY_LABEL[a.severity] ?? a.severity}
                  </Badge>
                  <Badge variant="outline" className="text-[10px]">{modeLabel(a.mode)}</Badge>
                </div>
                <p className="text-[11px] text-muted-foreground mt-0.5">
                  {a.queue} · réf. {a.reference} · {a.state ?? "—"} · {relativeAge(a.since)}
                </p>
              </div>
              <p className="text-sm font-semibold whitespace-nowrap">{formatGnf(a.amount_gnf)}</p>
            </Link>
          ))}
        </div>
      </Card>

      <p className="text-[11px] text-muted-foreground">
        Rôle actif : {role ?? "—"}. Les dossiers opérationnels restent en lecture seule pour la finance —{" "}
        {OPS_ESCALATION}.
        {data?.generated_at ? ` Lecture serveur ${new Date(data.generated_at).toLocaleTimeString()}.` : ""}
      </p>
    </ModulePage>
  );
}
