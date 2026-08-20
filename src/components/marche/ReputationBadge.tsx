import { useEffect, useState } from "react";
import { Star, ShieldCheck } from "lucide-react";
import {
  getReputationSummary,
  reputationDisplay,
  dimensionLabelFr,
  type ReputationSubjectKind,
  type ReputationSummary,
} from "@/lib/marche/reputation";

/**
 * Node 4 R9 — sanitized public reputation of one subject.
 * Renders only what the server published: an average over verified
 * transactions, a count, and optional dimension averages. Never a guess.
 */
export function ReputationBadge({
  subjectKind,
  subjectId,
  withDimensions = false,
  className = "",
}: {
  subjectKind: ReputationSubjectKind;
  subjectId: string;
  withDimensions?: boolean;
  className?: string;
}) {
  const [summary, setSummary] = useState<ReputationSummary | null>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const s = await getReputationSummary(subjectKind, subjectId);
        if (alive) setSummary(s);
      } catch {
        if (alive) setSummary(null);
      } finally {
        if (alive) setLoaded(true);
      }
    })();
    return () => {
      alive = false;
    };
  }, [subjectKind, subjectId]);

  if (!loaded) return null;
  const view = reputationDisplay(summary);

  if (!view.hasReputation) {
    return (
      <span
        className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-muted text-muted-foreground text-[10px] font-semibold ${className}`}
      >
        <Star className="w-3 h-3" /> Pas encore noté
      </span>
    );
  }

  return (
    <div className={`space-y-1 ${className}`}>
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-secondary/20 text-foreground text-[10px] font-semibold">
        <Star className="w-3 h-3 fill-secondary text-secondary" />
        {view.scoreLabel} / 5 · {view.countLabel}
      </span>
      <p className="text-[10px] text-muted-foreground flex items-center gap-1">
        <ShieldCheck className="w-3 h-3" /> Notes issues uniquement de transactions terminées
      </p>
      {withDimensions && summary && summary.dimensions.length > 0 && (
        <ul className="pt-1 space-y-0.5">
          {summary.dimensions.map((d) => (
            <li key={d.dimension} className="flex items-center justify-between text-[11px]">
              <span className="text-muted-foreground">{dimensionLabelFr(d.dimension)}</span>
              <span className="font-semibold">
                {d.average.toFixed(2).replace(".", ",")} ({d.count})
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}