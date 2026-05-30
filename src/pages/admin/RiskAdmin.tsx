import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { ShieldAlert, AlertTriangle, Activity, Wallet } from "lucide-react";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

type Alert = {
  id: string;
  source: "support" | "topup";
  severity: string;
  title: string;
  detail: string;
  created_at: string;
};

export default function RiskAdmin() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [counts, setCounts] = useState({ open: 0, high: 0, topup: 0, support: 0 });

  useEffect(() => {
    (async () => {
      setLoading(true);
      const [support, topup] = await Promise.all([
        supabase
          .from("support_issues")
          .select("id,severity,title,description,created_at,status")
          .in("severity", ["high", "critical"])
          .order("created_at", { ascending: false })
          .limit(50),
        supabase
          .from("topup_requests")
          .select("id,amount_gnf,status,created_at,customer_om_code_raw")
          .eq("status", "needs_review")
          .order("created_at", { ascending: false })
          .limit(50),
      ]);
      const list: Alert[] = [
        ...((support.data ?? []) as any[]).map((s) => ({
          id: s.id, source: "support" as const, severity: s.severity,
          title: s.title, detail: s.description ?? "—", created_at: s.created_at,
        })),
        ...((topup.data ?? []) as any[]).map((t) => ({
          id: t.id, source: "topup" as const, severity: "high",
          title: "Top-up en conflit", detail: `Montant ${t.amount_gnf} GNF · code ${t.customer_om_code_raw ?? "—"}`,
          created_at: t.created_at,
        })),
      ].sort((a, b) => +new Date(b.created_at) - +new Date(a.created_at));
      setAlerts(list);
      setCounts({
        open: list.length,
        high: list.filter((a) => a.severity === "high" || a.severity === "critical").length,
        topup: list.filter((a) => a.source === "topup").length,
        support: list.filter((a) => a.source === "support").length,
      });
      setLoading(false);
    })();
  }, []);

  return (
    <ModulePage module="risk" title="Fraude & Risque" subtitle="Alertes dérivées des tickets et conflits de paiement">
      <StatGrid items={[
        { label: "Alertes ouvertes", value: loading ? "…" : String(counts.open), icon: ShieldAlert },
        { label: "Sévérité haute", value: loading ? "…" : String(counts.high), icon: AlertTriangle },
        { label: "Conflits OM", value: loading ? "…" : String(counts.topup), icon: Wallet },
        { label: "Tickets support", value: loading ? "…" : String(counts.support), icon: Activity },
      ]} />
      <div className="space-y-2">
        {loading ? (
          <Card className="p-6 text-center text-sm text-muted-foreground">Chargement…</Card>
        ) : alerts.length === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">
            Aucune alerte de risque à afficher.
          </Card>
        ) : alerts.map((a) => (
          <Card key={`${a.source}-${a.id}`} className={`p-4 border-l-4 ${a.severity === "critical" || a.severity === "high" ? "border-l-rose-500" : "border-l-amber-500"}`}>
            <div className="flex items-start justify-between gap-3">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-mono text-xs text-muted-foreground">{a.source === "support" ? "SUP" : "OM"} · {a.id.slice(0, 8)}…</span>
                  <StatusBadge status={a.severity} />
                </div>
                <p className="font-medium text-sm">{a.title}</p>
                <p className="text-xs text-muted-foreground line-clamp-2">{a.detail}</p>
              </div>
              <span className="text-[11px] text-muted-foreground shrink-0">
                {new Date(a.created_at).toLocaleDateString("fr-FR")}
              </span>
            </div>
          </Card>
        ))}
      </div>
    </ModulePage>
  );
}
