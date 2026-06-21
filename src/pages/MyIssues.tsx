import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Loader2, LifeBuoy, ChevronLeft } from "lucide-react";
import { Seo } from "@/components/Seo";
import { SecondaryPageHeader } from "@/components/ui/SecondaryPageHeader";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { listMyIssues, type SupportIssue } from "@/lib/support/issues";
import {
  ISSUE_TYPE_LABEL,
  ISSUE_STATUS_LABEL,
  ISSUE_STATUS_TONE,
  ISSUE_SEVERITY_LABEL,
  ISSUE_SEVERITY_TONE,
} from "@/lib/support/constants";

const TONE: Record<"ok" | "warn" | "alert" | "muted", string> = {
  ok: "bg-emerald-500/10 text-emerald-700 border-emerald-500/30",
  warn: "bg-amber-500/10 text-amber-700 border-amber-500/30",
  alert: "bg-destructive/10 text-destructive border-destructive/30",
  muted: "bg-muted text-muted-foreground border-border/60",
};

function fmtWhen(iso: string) {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (min < 60) return `il y a ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `il y a ${h} h`;
  return new Date(iso).toLocaleDateString("fr-FR");
}

export default function MyIssues() {
  const [issues, setIssues] = useState<SupportIssue[] | null>(null);

  const load = async () => {
    const rows = await listMyIssues(50);
    setIssues(rows);
  };

  useEffect(() => {
    void load();
  }, []);

  return (
    <div className="min-h-screen bg-background pb-12">
      <Seo
        title="Mes signalements | CHOPCHOP"
        description="Suivez l'état de vos signalements envoyés au support CHOPCHOP."
        canonical="/help/issues"
      />
      <SecondaryPageHeader title="Mes signalements" />

      <div className="px-4 -mt-5 max-w-md mx-auto space-y-3">
        <Card className="p-3 flex items-center gap-3">
          <LifeBuoy className="w-5 h-5 text-primary" />
          <div className="text-xs text-muted-foreground">
            Vos demandes envoyées au support apparaissent ici avec leur statut.
            Les notes internes ne sont jamais affichées.
          </div>
        </Card>

        {issues === null ? (
          <Card className="p-6 text-center text-sm text-muted-foreground">
            <Loader2 className="w-4 h-4 animate-spin inline mr-2" />
            Chargement…
          </Card>
        ) : issues.length === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground border-dashed space-y-3">
            <p>Aucun signalement pour le moment.</p>
            <Button asChild variant="outline" size="sm">
              <Link to="/help">
                <ChevronLeft className="w-4 h-4 mr-1" /> Retour à l'aide
              </Link>
            </Button>
          </Card>
        ) : (
          issues.map((i) => (
            <Card key={i.id} className="p-3 space-y-2">
              <div className="flex items-center gap-2 flex-wrap">
                <span
                  className={`text-[11px] px-2 py-0.5 rounded-full border ${TONE[ISSUE_STATUS_TONE[i.status]]}`}
                >
                  {ISSUE_STATUS_LABEL[i.status]}
                </span>
                <span
                  className={`text-[11px] px-2 py-0.5 rounded-full border ${TONE[ISSUE_SEVERITY_TONE[i.severity]]}`}
                >
                  {ISSUE_SEVERITY_LABEL[i.severity]}
                </span>
                <span className="text-[11px] px-2 py-0.5 rounded-full border bg-muted text-muted-foreground border-border/60">
                  {ISSUE_TYPE_LABEL[i.issue_type]}
                </span>
              </div>
              <p className="text-sm font-medium">{i.title}</p>
              {i.description && (
                <p className="text-xs text-muted-foreground whitespace-pre-wrap line-clamp-3">
                  {i.description}
                </p>
              )}
              <p className="text-[11px] text-muted-foreground">
                Envoyé {fmtWhen(i.created_at)}
                {i.resolved_at ? ` · Résolu ${fmtWhen(i.resolved_at)}` : ""}
              </p>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}