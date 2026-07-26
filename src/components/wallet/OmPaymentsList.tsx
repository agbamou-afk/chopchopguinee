import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { LifeBuoy, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * Neutral OM Wallet payment list. Shows the authenticated user's own
 * Orange Money payment intents (RLS-scoped on the server), grouped by
 * status. Deliberately hides internal ledger balances, master wallet,
 * raw provider payloads and admin notes.
 */

type Intent = {
  id: string;
  amount_gnf: number;
  state: string;
  provider_reference: string | null;
  internal_reference: string | null;
  source_module: string | null;
  is_sandbox: boolean;
  created_at: string;
  rejection_reason: string | null;
};

type Refund = {
  id: string;
  payment_intent_id: string;
  status: string;
  amount_gnf: number;
  fee_gnf: number;
  source_module: string;
  is_sandbox: boolean;
  created_at: string;
  resolved_at: string | null;
};

const REFUND_LABEL: Record<string, { label: string; tone: string }> = {
  pending:      { label: "Remboursement en cours de vérification", tone: "bg-amber-500/15 text-amber-700 dark:text-amber-300" },
  in_review:    { label: "Remboursement en cours de vérification", tone: "bg-amber-500/15 text-amber-700 dark:text-amber-300" },
  paid:         { label: "Remboursé",                             tone: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300" },
  needs_review: { label: "Révision requise",                       tone: "bg-red-500/15 text-red-700 dark:text-red-300" },
  rejected:     { label: "Remboursement refusé",                   tone: "bg-muted text-muted-foreground" },
};

const STATE_LABEL: Record<string, { label: string; tone: string }> = {
  pending:         { label: "En attente de paiement", tone: "bg-muted text-muted-foreground" },
  processing:      { label: "Traitement",              tone: "bg-muted text-muted-foreground" },
  proof_submitted: { label: "Preuve envoyée",          tone: "bg-blue-500/15 text-blue-700 dark:text-blue-300" },
  in_review:       { label: "Vérification opérateur",  tone: "bg-amber-500/15 text-amber-700 dark:text-amber-300" },
  needs_review:    { label: "À revoir",                tone: "bg-amber-500/15 text-amber-700 dark:text-amber-300" },
  authorized:      { label: "Autorisé",                tone: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300" },
  confirmed:       { label: "Confirmé",                tone: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300" },
  failed:          { label: "Échec",                   tone: "bg-red-500/15 text-red-700 dark:text-red-300" },
  cancelled:       { label: "Annulé",                  tone: "bg-muted text-muted-foreground" },
  expired:         { label: "Expiré",                  tone: "bg-muted text-muted-foreground" },
  refunded:        { label: "Remboursé",               tone: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300" },
  reversed:        { label: "Annulé (remboursé)",      tone: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300" },
};

const MODULE_LABEL: Record<string, string> = {
  ride: "Course",
  repas: "Repas",
  marche: "Marché",
  topup: "Recharge",
};

export function OmPaymentsList() {
  const [rows, setRows] = useState<Intent[] | null>(null);
  const [refunds, setRefunds] = useState<Record<string, Refund>>({});
  const [err, setErr] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = async () => {
    setRefreshing(true);
    setErr(null);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setRows([]); setRefreshing(false); return; }
    const [{ data, error }, { data: rf }] = await Promise.all([
      supabase
        .from("payment_intents")
        .select("id,amount_gnf,state,provider_reference,internal_reference,source_module,is_sandbox,created_at,rejection_reason")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(30),
      supabase
        .from("payment_refund_requests")
        .select("id,payment_intent_id,status,amount_gnf,fee_gnf,source_module,is_sandbox,created_at,resolved_at")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(60),
    ]);
    if (error) {
      setErr("Impossible de charger vos paiements.");
    } else {
      setRows((data ?? []) as Intent[]);
      const map: Record<string, Refund> = {};
      for (const r of ((rf ?? []) as Refund[])) {
        // Keep the most recent refund per intent (query already sorted DESC)
        if (!map[r.payment_intent_id]) map[r.payment_intent_id] = r;
      }
      setRefunds(map);
    }
    setRefreshing(false);
  };

  useEffect(() => { void load(); }, []);

  if (rows === null) {
    return (
      <div className="space-y-2">
        {[0,1,2].map((i) => <Skeleton key={i} className="h-16 w-full rounded-xl" />)}
      </div>
    );
  }

  if (err) {
    return (
      <div className="rounded-2xl border border-border/60 p-4 text-sm text-muted-foreground">
        {err}
        <Button variant="ghost" size="sm" className="mt-2" onClick={load}>
          <RefreshCw className="w-3.5 h-3.5 mr-1.5" /> Réessayer
        </Button>
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border/60 p-6 text-center text-sm text-muted-foreground">
        Aucun paiement Orange Money pour le moment.
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <p className="text-[11px] uppercase tracking-[0.18em] font-semibold text-muted-foreground">
          Mes paiements Orange Money
        </p>
        <Button variant="ghost" size="sm" onClick={load} disabled={refreshing} className="h-7 px-2">
          <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? "animate-spin" : ""}`} />
        </Button>
      </div>
      <ul className="space-y-2">
        {rows.map((r) => {
          const meta = STATE_LABEL[r.state] ?? { label: r.state, tone: "bg-muted text-muted-foreground" };
          const mod = r.source_module ? (MODULE_LABEL[r.source_module] ?? r.source_module) : "Paiement";
          const rf = refunds[r.id];
          const rfMeta = rf ? (REFUND_LABEL[rf.status] ?? { label: rf.status, tone: "bg-muted" }) : null;
          return (
            <li key={r.id} className="rounded-xl border border-border/60 bg-card p-3">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-foreground truncate">
                    {mod} · {formatGNF(r.amount_gnf)}
                  </p>
                  <p className="text-[11px] text-muted-foreground truncate">
                    {new Date(r.created_at).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" })}
                    {r.internal_reference ? ` · Réf. ${r.internal_reference}` : ""}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-1 shrink-0">
                  <Badge className={`${meta.tone} border-0 text-[10px]`}>{meta.label}</Badge>
                  {r.is_sandbox && (
                    <Badge variant="outline" className="text-[10px] border-amber-500/40 text-amber-700 dark:text-amber-300">
                      Sandbox
                    </Badge>
                  )}
                </div>
              </div>
              {rf && rfMeta && (
                <div className="mt-2 pt-2 border-t border-border/40 flex items-center justify-between gap-2 text-[11px]">
                  <div className="min-w-0">
                    <p className="text-foreground/80">
                      {rfMeta.label}
                      {rf.fee_gnf > 0 && ` · Frais ${formatGNF(rf.fee_gnf)}`}
                    </p>
                    <p className="text-muted-foreground">
                      Remboursement {formatGNF(rf.amount_gnf)} · Demandé {new Date(rf.created_at).toLocaleDateString("fr-FR")}
                      {rf.resolved_at ? ` · Résolu ${new Date(rf.resolved_at).toLocaleDateString("fr-FR")}` : ""}
                    </p>
                  </div>
                  <Badge className={`${rfMeta.tone} border-0 text-[10px] shrink-0`}>{rf.status}</Badge>
                </div>
              )}
              {r.state === "failed" && r.rejection_reason && (
                <p className="mt-1.5 text-[11px] text-red-700 dark:text-red-300">{r.rejection_reason}</p>
              )}
              {((r.state === "in_review" || r.state === "needs_review" || r.state === "failed") ||
                (rf && (rf.status === "needs_review"))) && (
                <a
                  href="/help/issues"
                  className="mt-2 inline-flex items-center gap-1 text-[11px] font-medium text-primary"
                >
                  <LifeBuoy className="w-3 h-3" /> Ouvrir un signalement
                </a>
              )}
            </li>
          );
        })}
      </ul>
      <p className="text-[10px] text-muted-foreground text-center pt-1">
        Aucun solde n'est stocké. Chaque paiement est vérifié par un opérateur CHOPCHOP.
      </p>
    </div>
  );
}