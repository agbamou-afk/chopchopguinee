/**
 * Holder-scoped one-time custody code display (R6).
 *
 * The code is fetched from `repas_custody_code_view`, which only ever returns
 * it to its designated holder. Nothing is cached locally: reopening the app
 * re-fetches from the server.
 */
import { useCallback, useEffect, useState } from "react";
import { Loader2, QrCode, ShieldCheck } from "lucide-react";
import { fetchCustodyCode, type CustodyCodeView, type CustodyKind } from "@/lib/repas/custody";

interface Props {
  orderId: string;
  kind: CustodyKind;
  /** French one-liner telling the holder when to reveal the code. */
  instruction: string;
  title: string;
}

export function CustodyCodeCard({ orderId, kind, instruction, title }: Props) {
  const [view, setView] = useState<CustodyCodeView | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setView(await fetchCustodyCode(orderId, kind));
      setErr(null);
    } catch (e) {
      setView(null);
      setErr(e instanceof Error ? e.message : "Indisponible");
    } finally {
      setLoading(false);
    }
  }, [orderId, kind]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) {
    return (
      <div className="rounded-xl border border-border/60 bg-muted/30 p-3 flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="w-4 h-4 animate-spin" /> Chargement du code…
      </div>
    );
  }
  // Not the holder, or nothing issued yet → render nothing rather than a stub.
  if (err || !view || !view.issued) return null;
  if (view.expired || view.active === false) {
    return (
      <div className="rounded-xl border border-border/60 bg-muted/30 p-3">
        <p className="text-xs font-semibold text-muted-foreground uppercase">{title}</p>
        <p className="text-sm text-muted-foreground mt-1">
          {view.disputed
            ? "Code désactivé — commande en litige."
            : "Code expiré — commande clôturée."}
        </p>
      </div>
    );
  }
  if (view.consumed) {
    return (
      <div className="rounded-xl border border-primary/40 bg-primary/5 p-3">
        <p className="text-xs font-semibold text-primary uppercase">{title}</p>
        <p className="text-sm text-foreground mt-1">Code déjà utilisé — remise confirmée.</p>
      </div>
    );
  }
  if (view.locked) {
    return (
      <div className="rounded-xl border border-destructive/40 bg-destructive/5 p-3">
        <p className="text-xs font-semibold text-destructive uppercase">{title}</p>
        <p className="text-sm text-foreground mt-1">
          Code bloqué après 5 tentatives. Contactez le support.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-primary/40 bg-primary/5 p-3">
      <p className="text-xs font-semibold text-primary uppercase inline-flex items-center gap-1">
        <QrCode className="w-3 h-3" /> {title}
      </p>
      <p className="mt-2 text-3xl font-extrabold tracking-[0.35em] tabular-nums text-foreground text-center">
        {view.code ?? "——————"}
      </p>
      <p className="mt-2 text-xs text-muted-foreground">{instruction}</p>
      <p className="mt-1 inline-flex items-center gap-1 text-[10px] text-muted-foreground">
        <ShieldCheck className="w-3 h-3 text-primary" /> Code à usage unique — 5 tentatives maximum.
      </p>
    </div>
  );
}
