import { useCallback, useEffect, useState } from "react";
import { Loader2, ShieldCheck, Star } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import {
  dimensionLabelFr,
  getReputationEligibility,
  reputationErrorFr,
  submitReputation,
  SUBJECT_LABEL_FR,
  type ReputationEligibility,
  type ReputationSubjectOption,
  type ReputationTransactionKind,
} from "@/lib/marche/reputation";

/**
 * Node 4 R9 — verified rating sheet.
 *
 * The sheet renders exactly what the server declared rateable: the customer
 * never chooses who is rated, and a subject already rated is closed forever.
 */
export function RatingSheet({
  open,
  onOpenChange,
  transactionKind,
  transactionId,
  onRated,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  transactionKind: ReputationTransactionKind;
  transactionId: string;
  onRated?: () => void;
}) {
  const [eligibility, setEligibility] = useState<ReputationEligibility | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [scores, setScores] = useState<Record<string, number>>({});
  const [dims, setDims] = useState<Record<string, Record<string, number>>>({});
  const [comments, setComments] = useState<Record<string, string>>({});

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      setEligibility(await getReputationEligibility(transactionKind, transactionId));
    } catch (e) {
      setEligibility(null);
      toast.error(reputationErrorFr((e as Error)?.message ?? ""));
    } finally {
      setLoading(false);
    }
  }, [transactionKind, transactionId]);

  useEffect(() => {
    if (open) void reload();
  }, [open, reload]);

  const send = async (subject: ReputationSubjectOption) => {
    const overall = scores[subject.subject_kind];
    if (!overall) {
      toast.error("Donnez une note de 1 à 5.");
      return;
    }
    setBusy(true);
    try {
      const res = await submitReputation({
        transactionKind,
        transactionId,
        subjectKind: subject.subject_kind,
        overallScore: overall,
        comment: comments[subject.subject_kind],
        dimensions: dims[subject.subject_kind],
      });
      toast.success(res.status === "RECORDED" ? "Merci, votre note est enregistrée." : "Vous aviez déjà noté.");
      onRated?.();
      await reload();
    } catch (e) {
      toast.error(reputationErrorFr((e as Error)?.message ?? ""));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-2xl max-h-[88vh] overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <Star className="w-4 h-4 text-secondary" /> Noter cette transaction
          </SheetTitle>
        </SheetHeader>

        {loading ? (
          <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
            <Loader2 className="w-4 h-4 animate-spin" /> Vérification…
          </div>
        ) : !eligibility?.eligible ? (
          <p className="py-6 text-sm text-muted-foreground">
            {reputationErrorFr(eligibility?.reason ?? "TRANSACTION_NOT_COMPLETED")}
          </p>
        ) : (
          <div className="space-y-4 py-3">
            {eligibility.subjects.map((s) => (
              <div key={s.subject_kind} className="rounded-2xl border border-border/60 bg-card p-3 space-y-3">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-semibold">
                    {s.subject_label || SUBJECT_LABEL_FR[s.subject_kind]}
                  </p>
                  {s.already_rated && (
                    <span className="text-[10px] font-semibold text-muted-foreground">
                      Déjà noté {s.my_overall_score}/5
                    </span>
                  )}
                </div>

                {s.already_rated ? (
                  <p className="text-[11px] text-muted-foreground">
                    Une note enregistrée est définitive.
                  </p>
                ) : (
                  <>
                    <ScoreRow
                      value={scores[s.subject_kind] ?? 0}
                      onChange={(v) => setScores((p) => ({ ...p, [s.subject_kind]: v }))}
                    />
                    <div className="space-y-1.5">
                      {s.dimensions.map((d) => (
                        <div key={d} className="flex items-center justify-between gap-2">
                          <span className="text-[11px] text-muted-foreground">{dimensionLabelFr(d)}</span>
                          <ScoreRow
                            small
                            value={dims[s.subject_kind]?.[d] ?? 0}
                            onChange={(v) =>
                              setDims((p) => ({
                                ...p,
                                [s.subject_kind]: { ...(p[s.subject_kind] ?? {}), [d]: v },
                              }))
                            }
                          />
                        </div>
                      ))}
                    </div>
                    <Textarea
                      value={comments[s.subject_kind] ?? ""}
                      maxLength={1000}
                      onChange={(e) =>
                        setComments((p) => ({ ...p, [s.subject_kind]: e.target.value }))
                      }
                      placeholder="Commentaire (optionnel)"
                      className="min-h-[64px]"
                    />
                    <Button className="w-full" disabled={busy} onClick={() => send(s)}>
                      {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Envoyer ma note"}
                    </Button>
                  </>
                )}
              </div>
            ))}
            <p className="text-[11px] text-muted-foreground flex items-start gap-1">
              <ShieldCheck className="w-3 h-3 mt-0.5 shrink-0" />
              Seuls les clients d'une transaction terminée peuvent noter, une seule fois, et la note
              ne peut plus être modifiée.
            </p>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}

function ScoreRow({
  value,
  onChange,
  small = false,
}: {
  value: number;
  onChange: (v: number) => void;
  small?: boolean;
}) {
  const size = small ? "w-4 h-4" : "w-7 h-7";
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map((i) => (
        <button
          key={i}
          type="button"
          aria-label={`${i} sur 5`}
          onClick={() => onChange(i)}
          className="p-0.5"
        >
          <Star
            className={`${size} ${i <= value ? "fill-secondary text-secondary" : "text-muted-foreground/40"}`}
          />
        </button>
      ))}
    </div>
  );
}