import { useCallback, useEffect, useRef, useState } from "react";
import { Loader2, ShoppingBasket, Trash2, ShieldCheck, Info, CheckCircle2 } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/marche";
import {
  authorizeProcurement,
  confidenceLabelFr,
  createProcurementRequestIdStore,
  insufficientDataMessageFr,
  procurementErrorFr,
  quoteProcurement,
  type ProcurementLineInput,
  type ProcurementQuote,
  type ProcurementRequest,
} from "@/lib/marche/procurement";

export interface BasketLine extends ProcurementLineInput {
  label_fr: string;
  option_label_fr: string;
}

/**
 * R6.5 customer surface: basket -> server quote -> explicit spending ceiling
 * -> authorization. No client price math, no settlement, no shopper controls.
 */
export function ProcurementBasketSheet({
  open,
  onOpenChange,
  lines,
  onRemove,
  onAuthorized,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  lines: BasketLine[];
  onRemove: (index: number) => void;
  onAuthorized?: (r: ProcurementRequest) => void;
}) {
  const [quote, setQuote] = useState<ProcurementQuote | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [bufferPct, setBufferPct] = useState(0);
  const [request, setRequest] = useState<ProcurementRequest | null>(null);
  const keys = useRef(createProcurementRequestIdStore("staples-basket"));

  const refresh = useCallback(async () => {
    if (!open || lines.length === 0) return;
    setLoading(true);
    setQuoteError(null);
    try {
      setQuote(await quoteProcurement(lines));
    } catch (e) {
      setQuote(null);
      setQuoteError(procurementErrorFr((e as Error)?.message ?? ""));
    } finally {
      setLoading(false);
    }
  }, [open, lines]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const allowed = quote?.authorization_allowed === true && (quote?.min_ceiling_gnf ?? 0) > 0;
  const minCeiling = quote?.min_ceiling_gnf ?? 0;
  const maxCeiling = quote?.max_ceiling_gnf ?? 0;
  const ceiling = allowed
    ? Math.min(Math.floor(minCeiling * (1 + bufferPct / 100)), maxCeiling || Number.MAX_SAFE_INTEGER)
    : 0;

  const authorize = async () => {
    if (!allowed) return;
    setBusy(true);
    setAuthError(null);
    try {
      const key = keys.current.idFor(lines, ceiling);
      const r = await authorizeProcurement({ lines, ceilingGnf: ceiling, clientRequestId: key });
      setRequest(r);
      onAuthorized?.(r);
    } catch (e) {
      setAuthError(procurementErrorFr((e as Error)?.message ?? ""));
    } finally {
      setBusy(false);
    }
  };

  const close = (v: boolean) => {
    if (!v) {
      setRequest(null);
      setAuthError(null);
      setBufferPct(0);
    }
    onOpenChange(v);
  };

  return (
    <Sheet open={open} onOpenChange={close}>
      <SheetContent side="bottom" className="rounded-t-2xl max-h-[92vh] overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <ShoppingBasket className="w-4 h-4 text-primary" /> Panier Essentiels
          </SheetTitle>
        </SheetHeader>

        {request ? (
          <div className="space-y-3 py-3" data-testid="procurement-authorized">
            <div className="flex items-center gap-2 text-sm font-semibold text-primary">
              <CheckCircle2 className="w-4 h-4" /> Achat autorisé
            </div>
            <div className="rounded-xl border border-border/60 bg-card p-3 space-y-1">
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Estimation CHOP CHOP</span>
                <span className="font-medium">{formatGNF(request.estimated_subtotal_gnf ?? 0)}</span>
              </div>
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Montant maximum autorisé</span>
                <span className="font-bold">{formatGNF(request.authorized_ceiling_gnf)}</span>
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Seul le montant réellement dépensé au marché sera débité, dans la limite du maximum
              autorisé. Le reste est automatiquement libéré.
            </p>
            <Button className="w-full" onClick={() => close(false)}>Fermer</Button>
          </div>
        ) : (
          <div className="space-y-3 py-3">
            {lines.length === 0 ? (
              <p className="text-sm text-muted-foreground">Votre panier est vide.</p>
            ) : (
              <div className="space-y-2">
                {lines.map((l, i) => (
                  <div key={`${l.commodity_code}-${l.option_code}-${i}`} className="flex items-center gap-3 rounded-xl border border-border/60 bg-card p-3">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{l.label_fr}</p>
                      <p className="text-[11px] text-muted-foreground truncate">
                        {l.qty} × {l.option_label_fr}
                      </p>
                    </div>
                    <button aria-label="Retirer" onClick={() => onRemove(i)} className="text-muted-foreground">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))}
              </div>
            )}

            {loading && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <Loader2 className="w-3.5 h-3.5 animate-spin" /> Estimation en cours…
              </div>
            )}

            {quoteError && <p className="text-xs text-destructive" data-testid="quote-error">{quoteError}</p>}

            {quote && !allowed && (
              <div className="rounded-xl border border-dashed border-border bg-muted/30 p-3" data-testid="insufficient-data">
                <p className="text-xs font-semibold text-foreground">Estimation indisponible</p>
                <p className="mt-1 text-[11px] text-muted-foreground">{insufficientDataMessageFr(quote)}</p>
                <p className="mt-1 text-[11px] text-muted-foreground">
                  Aucun prix n'est inventé : l'autorisation reste bloquée tant que CHOP CHOP n'a pas
                  de relevés fiables.
                </p>
              </div>
            )}

            {quote && allowed && (
              <div className="space-y-3">
                <div className="rounded-xl border border-border/60 bg-card p-3 space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Estimation (indicative)</span>
                    <span className="font-medium" data-testid="estimate-amount">{formatGNF(minCeiling)}</span>
                  </div>
                  {confidenceLabelFr(quote.estimate_confidence) && (
                    <p className="text-[11px] text-muted-foreground">
                      {confidenceLabelFr(quote.estimate_confidence)} · {quote.estimate_sample_count ?? 0} relevés
                    </p>
                  )}
                  <p className="text-[11px] text-muted-foreground flex items-start gap-1">
                    <Info className="w-3 h-3 mt-0.5 shrink-0" />
                    {quote.disclaimer_fr ?? "Estimation — le prix réel au marché peut varier."} Ce
                    n'est pas un prix d'achat garanti.
                  </p>
                </div>

                <div className="rounded-xl border border-primary/40 bg-primary/5 p-3 space-y-2">
                  <p className="text-xs font-semibold text-foreground flex items-center gap-1.5">
                    <ShieldCheck className="w-3.5 h-3.5 text-primary" /> Montant maximum autorisé
                  </p>
                  <div className="flex items-center gap-2">
                    {[0, 10, 20].map((p) => (
                      <button
                        key={p}
                        onClick={() => setBufferPct(p)}
                        data-testid={`buffer-${p}`}
                        className={`flex-1 rounded-xl px-2 py-1.5 text-[11px] font-semibold ${
                          bufferPct === p
                            ? "gradient-wallet text-primary-foreground"
                            : "bg-card border border-border text-muted-foreground"
                        }`}
                      >
                        {p === 0 ? "Estimation" : `+${p}%`}
                      </button>
                    ))}
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Plafond</span>
                    <span className="text-base font-bold" data-testid="ceiling-amount">{formatGNF(ceiling)}</span>
                  </div>
                  <p className="text-[11px] text-muted-foreground">
                    Ce montant est bloqué sur votre solde. CHOP CHOP ne débite que la dépense réelle
                    au marché, jusqu'à ce plafond ; le solde non utilisé est libéré.
                  </p>
                </div>
              </div>
            )}

            {authError && <p className="text-xs text-destructive" data-testid="auth-error">{authError}</p>}

            <Button
              className="w-full"
              onClick={authorize}
              disabled={!allowed || busy || lines.length === 0}
              data-testid="authorize-button"
            >
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Autoriser le montant maximum"}
            </Button>
            <p className="text-[11px] text-muted-foreground text-center">
              L'estimation et le plafond sont calculés par CHOP CHOP.
            </p>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
