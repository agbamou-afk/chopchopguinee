import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import {
  Search,
  Sparkles,
  Loader2,
  ArrowRight,
  Bike,
  Car,
  UtensilsCrossed,
  ShoppingBag,
  Send,
  QrCode,
  Wallet,
  LifeBuoy,
  Package,
  MapPin,
  Shield,
  X,
} from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import {
  defaultSuggestions,
  groupResults,
  routeQuery,
  type CommandIntent,
  type CommandResult,
} from "@/lib/ai/commandRouter";
import { AIService } from "@/lib/ai";
import { useAuthGuard } from "@/hooks/useAuthGuard";
import { useAuth } from "@/contexts/AuthContext";
import { cn } from "@/lib/utils";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAction: (intent: CommandIntent, params?: { destination?: string }) => void;
  location?: string;
}

const ICONS: Record<CommandIntent, typeof Bike> = {
  moto: Bike,
  toktok: Car,
  food: UtensilsCrossed,
  market: ShoppingBag,
  send: Send,
  parcel: Package,
  scan: QrCode,
  wallet: Wallet,
  support: LifeBuoy,
  orders: Package,
  admin: Shield,
  navigate: MapPin,
};

const TINTS: Partial<Record<CommandIntent, string>> = {
  moto: "bg-primary/10 text-primary",
  toktok: "bg-primary/10 text-primary",
  food: "bg-[hsl(8_78%_55%/0.10)] text-[hsl(8_78%_45%)]",
  market: "bg-secondary/30 text-foreground",
  send: "bg-primary/10 text-primary",
  parcel: "bg-[hsl(45_90%_55%/0.15)] text-[hsl(38_80%_38%)]",
  wallet: "bg-primary/10 text-primary",
  scan: "bg-secondary/30 text-foreground",
  support: "bg-[hsl(45_90%_55%/0.15)] text-[hsl(38_80%_38%)]",
  orders: "bg-primary/10 text-primary",
  admin: "bg-foreground/10 text-foreground",
  navigate: "bg-secondary/30 text-foreground",
};

export function CommandBarSheet({ open, onOpenChange, onAction, location }: Props) {
  const [query, setQuery] = useState("");
  const [aiHint, setAiHint] = useState<{
    text: string;
    suggested?: CommandIntent | "none";
    label?: string;
  } | null>(null);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState<string | null>(null);
  const aiAbort = useRef<number | null>(null);
  const navigate = useNavigate();
  const { requireAuth } = useAuthGuard();
  const { isAdmin } = useAuth();

  const isEmpty = query.trim().length === 0;

  const groups = useMemo(() => {
    const results = isEmpty ? defaultSuggestions({ isAdmin }) : routeQuery(query, { isAdmin });
    return groupResults(results);
  }, [query, isEmpty, isAdmin]);

  // Reset on open
  useEffect(() => {
    if (open) {
      setQuery("");
      setAiHint(null);
      setAiError(null);
      setAiLoading(false);
    }
  }, [open]);

  // Emit query/intent telemetry — debounced, never includes raw text.
  useEffect(() => {
    if (!open) return;
    const q = query.trim();
    if (!q) return;
    const t = window.setTimeout(() => {
      const flatIntents = Array.from(new Set(groups.flatMap((g) => g.items.map((i) => i.intent))));
      Analytics.track("commandbar.query.submitted", {
        metadata: { query_length: q.length, result_count: groups.reduce((n, g) => n + g.items.length, 0) },
      });
      if (flatIntents.length > 0) {
        Analytics.track("commandbar.intent.detected", { metadata: { intents: flatIntents } });
      } else {
        Analytics.track("commandbar.no_results", { metadata: { query_length: q.length } });
      }
    }, 350);
    return () => window.clearTimeout(t);
  }, [query, groups, open]);

  // AI fallback — only for queries ≥ 4 chars where local router returned just
  // the generic "Demander de l'aide" fallback. Debounced.
  useEffect(() => {
    setAiHint(null);
    setAiError(null);
    if (aiAbort.current) window.clearTimeout(aiAbort.current);
    const q = query.trim();
    if (q.length < 4) return;
    const localOnlyHelp =
      groups.length === 1 && groups[0].items.every((i) => i.intent === "support");
    if (!localOnlyHelp) return;

    aiAbort.current = window.setTimeout(async () => {
      setAiLoading(true);
      const res = await AIService.askHome(q, { location });
      setAiLoading(false);
      if (res.ok !== true) {
        setAiError((res as { error?: string }).error || "L'assistant n'est pas disponible.");
        return;
      }
      setAiHint({
        text: res.json?.answer || res.text || "",
        suggested: res.json?.suggested_action,
        label: res.json?.suggested_action_label,
      });
    }, 450);
    return () => {
      if (aiAbort.current) window.clearTimeout(aiAbort.current);
    };
  }, [query, groups, location]);

  function fire(intent: CommandIntent, params?: { destination?: string }) {
    Analytics.track("commandbar.result.clicked", { metadata: { intent, has_destination: !!params?.destination } });
    Analytics.track("search.routed_to_service", { metadata: { intent, destination: params?.destination ?? null } });
    if (intent === "support") {
      onOpenChange(false);
      setTimeout(() => navigate("/help"), 80);
      return;
    }
    if (intent === "admin") {
      if (!isAdmin) return;
      onOpenChange(false);
      const path = params?.destination?.startsWith("/admin") ? params.destination : "/admin";
      setTimeout(() => navigate(path), 80);
      return;
    }
    if (!requireAuth()) return;
    onOpenChange(false);
    setTimeout(() => onAction(intent, params), 80);
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="bottom"
        className="h-[88vh] p-0 flex flex-col rounded-t-3xl gap-0"
      >
        {/* Search header */}
        <div className="px-4 pt-4 pb-3 border-b border-border/60 bg-background sticky top-0">
          <div className="flex items-center gap-2">
            <div className="flex-1 h-12 flex items-center gap-3 px-4 bg-card rounded-2xl border border-border focus-within:border-primary/60 transition-colors">
              <Search className="w-4 h-4 text-muted-foreground shrink-0" />
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Que voulez-vous faire ?"
                className="flex-1 bg-transparent outline-none text-sm placeholder:text-muted-foreground"
                aria-label="Recherche intelligente"
              />
              {query && (
                <button
                  onClick={() => setQuery("")}
                  className="text-muted-foreground hover:text-foreground"
                  aria-label="Effacer"
                >
                  <X className="w-4 h-4" />
                </button>
              )}
            </div>
            <button
              onClick={() => onOpenChange(false)}
              className="text-sm text-muted-foreground px-2"
            >
              Annuler
            </button>
          </div>
          <p className="text-[11px] text-muted-foreground mt-2 flex items-center gap-1">
            <Sparkles className="w-3 h-3 text-primary" />
            Tapez ou choisissez — l'assistant vous oriente vers la bonne action.
          </p>
        </div>

        {/* Results */}
        <div className="flex-1 overflow-y-auto px-3 py-4 space-y-5">
          {groups.map((g) => (
            <ResultGroup
              key={g.group}
              label={g.label}
              items={g.items}
              onPick={(r) => fire(r.intent, r.destination ? { destination: r.destination } : undefined)}
            />
          ))}

          {/* AI fallback hint */}
          <AnimatePresence>
            {(aiLoading || aiHint || aiError) && (
              <motion.div
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="mx-1 rounded-2xl border border-primary/30 bg-primary/5 p-4 space-y-3"
              >
                <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-primary">
                  <Sparkles className="w-3.5 h-3.5" />
                  Assistant CHOP CHOP
                </div>
                {aiLoading && (
                  <p className="text-sm text-muted-foreground inline-flex items-center gap-2">
                    <Loader2 className="w-3.5 h-3.5 animate-spin" /> Réflexion…
                  </p>
                )}
                {aiError && <p className="text-sm text-destructive">{aiError}</p>}
                {aiHint && (
                  <>
                    <p className="text-sm text-foreground leading-relaxed">{aiHint.text}</p>
                    {aiHint.suggested && aiHint.suggested !== "none" && (
                      <button
                        onClick={() => fire(aiHint.suggested as CommandIntent)}
                        className="w-full inline-flex items-center justify-center gap-2 h-10 rounded-xl bg-primary text-primary-foreground text-sm font-medium"
                      >
                        {aiHint.label || "Continuer"}
                        <ArrowRight className="w-4 h-4" />
                      </button>
                    )}
                  </>
                )}
              </motion.div>
            )}
          </AnimatePresence>

          {!isEmpty && groups.length === 0 && !aiLoading && !aiHint && !aiError && (
            <EmptyState query={query} onAskHelp={() => fire("support")} />
          )}

          <p className="text-[11px] text-center text-muted-foreground/70 pt-2">
            Les résultats sont des raccourcis. Aucun prix, chauffeur ou commande n'est inventé.
          </p>
        </div>
      </SheetContent>
    </Sheet>
  );
}

function ResultGroup({
  label,
  items,
  onPick,
}: {
  label: string;
  items: CommandResult[];
  onPick: (r: CommandResult) => void;
}) {
  return (
    <section>
      <h3 className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground px-2 mb-2">
        {label}
      </h3>
      <div className="space-y-1.5">
        {items.map((r) => {
          const Icon = ICONS[r.intent];
          return (
            <button
              key={r.id}
              onClick={() => onPick(r)}
              className="w-full flex items-center gap-3 px-3 py-3 bg-card border border-border/60 rounded-2xl text-left hover:border-primary/40 hover:bg-card/80 transition-colors active:scale-[0.99]"
            >
              <div
                className={cn(
                  "w-10 h-10 rounded-xl flex items-center justify-center shrink-0",
                  TINTS[r.intent] ?? "bg-secondary/30 text-foreground",
                )}
              >
                <Icon className="w-5 h-5" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-foreground truncate">{r.title}</p>
                {r.subtitle && (
                  <p className="text-[11px] text-muted-foreground truncate">{r.subtitle}</p>
                )}
              </div>
              <ArrowRight className="w-4 h-4 text-muted-foreground shrink-0" />
            </button>
          );
        })}
      </div>
    </section>
  );
}

function EmptyState({ query, onAskHelp }: { query: string; onAskHelp: () => void }) {
  return (
    <div className="text-center py-10 space-y-3">
      <div className="w-12 h-12 mx-auto rounded-2xl bg-muted/40 flex items-center justify-center">
        <Search className="w-5 h-5 text-muted-foreground" />
      </div>
      <p className="text-sm text-muted-foreground">
        Rien trouvé pour <span className="font-medium text-foreground">"{query}"</span>.
      </p>
      <button
        onClick={onAskHelp}
        className="inline-flex items-center gap-2 text-sm font-medium text-primary"
      >
        Demander à l'équipe <ArrowRight className="w-4 h-4" />
      </button>
    </div>
  );
}