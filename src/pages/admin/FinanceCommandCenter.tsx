import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle, ArrowDownToLine, ArrowUpFromLine, Landmark, RefreshCw, Receipt, Wallet,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";

const REFRESH_MS = 60_000;

interface QueueCard {
  key: string;
  label: string;
  value: number | null;
  href: string;
  hint: string;
  mode: "direct" | "approval";
  icon: typeof Wallet;
}

async function safeCount(table: string, build?: (q: any) => any): Promise<number | null> {
  try {
    let q: any = (supabase.from as any)(table).select("*", { count: "exact", head: true });
    if (build) q = build(q);
    const { count, error } = await q;
    if (error) return null;
    return count ?? 0;
  } catch {
    return null;
  }
}

export default function FinanceCommandCenter() {
  const { role } = useAdminAuth();
  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const [queues, setQueues] = useState<QueueCard[]>([]);
  const [exceptions, setExceptions] = useState<number | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [topups, cashouts, settlements, refunds, intents] = await Promise.all([
      safeCount("topup_requests", (q) => q.in("status", ["pending", "proof_submitted", "needs_review"])),
      safeCount("driver_cashout_requests", (q) => q.eq("status", "pending")),
      safeCount("merchant_settlement_requests", (q) => q.eq("status", "pending")),
      safeCount("payment_refund_requests", (q) => q.eq("status", "pending")),
      safeCount("payment_intents", (q) => q.in("state", ["needs_review", "in_review"])),
    ]);

    setQueues([
      { key: "topups", label: "Recharges à vérifier", value: topups, href: "/admin/wallet/reconciliation",
        hint: "Aucun crédit sans preuve", mode: "direct", icon: ArrowDownToLine },
      { key: "cashouts", label: "Retraits chauffeurs", value: cashouts, href: "/admin/wallet/driver-cashouts",
        hint: "Confirmation à quatre yeux", mode: "approval", icon: ArrowUpFromLine },
      { key: "settlements", label: "Règlements marchands", value: settlements, href: "/admin/wallet/payouts",
        hint: "Confirmation à quatre yeux", mode: "approval", icon: Receipt },
      { key: "refunds", label: "Remboursements", value: refunds, href: "/admin/payments",
        hint: "Au-delà du seuil : approbation", mode: "approval", icon: Wallet },
      { key: "intents", label: "Paiements en revue", value: intents, href: "/admin/payments",
        hint: "Vérification opérateur", mode: "direct", icon: AlertTriangle },
    ]);

    try {
      const { data, error } = await (supabase.rpc as any)("finance_treasury_exceptions");
      setExceptions(error ? null : Array.isArray(data) ? data.length : null);
    } catch {
      setExceptions(null);
    }

    setLastRefresh(new Date());
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
    const id = window.setInterval(() => {
      if (!document.hidden) load();
    }, REFRESH_MS);
    return () => window.clearInterval(id);
  }, [load]);

  return (
    <ModulePage
      module="payments"
      title="Centre finance"
      subtitle="Files financières réelles. Aucun mouvement automatique, aucune estimation."
      actions={
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCw className={`w-4 h-4 mr-1 ${loading ? "animate-spin" : ""}`} />
          Actualiser
        </Button>
      }
    >
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {queues.map((q) => {
          const Icon = q.icon;
          return (
            <Link key={q.key} to={q.href}>
              <Card className="p-4 h-full hover:border-primary/50 transition-colors">
                <div className="flex items-start justify-between gap-2">
                  <Icon className="w-4 h-4 text-muted-foreground" />
                  <Badge variant="outline" className="text-[10px]">
                    {q.mode === "approval" ? "Approbation requise" : "Exécution directe"}
                  </Badge>
                </div>
                <p className="text-2xl font-semibold mt-3">
                  {q.value === null ? "—" : q.value}
                </p>
                <p className="text-sm font-medium">{q.label}</p>
                <p className="text-[11px] text-muted-foreground mt-1">
                  {q.value === null ? "Non activé" : q.hint}
                </p>
              </Card>
            </Link>
          );
        })}
      </div>

      <Card className="p-4">
        <div className="flex items-center justify-between gap-3">
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
            <p className="text-2xl font-semibold">{exceptions === null ? "—" : exceptions}</p>
            <Link to="/admin/treasury" className="text-[11px] text-primary underline">
              Ouvrir la trésorerie
            </Link>
          </div>
        </div>
      </Card>

      <p className="text-[11px] text-muted-foreground">
        Rôle actif : {role ?? "—"}. Les modules opérationnels restent en lecture seule pour la finance.
        {lastRefresh ? ` Dernière actualisation ${lastRefresh.toLocaleTimeString()}.` : ""}
      </p>
    </ModulePage>
  );
}
