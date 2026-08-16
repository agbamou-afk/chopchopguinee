import { useCallback, useEffect, useState } from "react";
import { ChevronRight, Package, Search, X } from "lucide-react";
import {
  discoverStaples,
  getStaple,
  listStapleCategories,
  normalizationLabel,
  type StapleCategory,
  type StapleDetail,
  type StapleSummary,
} from "@/lib/marche/staples";
import { LoadingState } from "@/components/ui/LoadingState";
import { EmptyState } from "@/components/ui/EmptyState";

/** R6 Essentiels — read-only reference catalog. No price, no cart, no ordering. */
export function StaplesView() {
  const [categories, setCategories] = useState<StapleCategory[]>([]);
  const [category, setCategory] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [items, setItems] = useState<StapleSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [detail, setDetail] = useState<StapleDetail | null>(null);

  useEffect(() => {
    listStapleCategories().then(setCategories).catch(() => setCategories([]));
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    const rows = await discoverStaples({ search, category, limit: 100 }).catch(() => []);
    setItems(rows);
    setLoading(false);
  }, [search, category]);

  useEffect(() => {
    const t = setTimeout(load, 200);
    return () => clearTimeout(t);
  }, [load]);

  return (
    <section className="space-y-3">
      <div className="h-12 flex items-center gap-3 px-4 bg-card rounded-2xl border border-border/60">
        <Search className="w-4 h-4 text-muted-foreground" />
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Riz, huile, oignon…"
          className="flex-1 bg-transparent text-sm text-foreground focus:outline-none placeholder:text-muted-foreground"
        />
        {search && (
          <button onClick={() => setSearch("")} aria-label="Effacer">
            <X className="w-4 h-4 text-muted-foreground" />
          </button>
        )}
      </div>

      <div className="flex items-center gap-2 overflow-x-auto scrollbar-none -mx-1 px-1">
        <button
          onClick={() => setCategory(null)}
          className={`shrink-0 px-3 py-1.5 rounded-full text-[11px] font-semibold ${
            category === null
              ? "gradient-wallet text-primary-foreground"
              : "bg-card border border-border text-muted-foreground"
          }`}
        >
          Tous
        </button>
        {categories.map((c) => (
          <button
            key={c.code}
            onClick={() => setCategory(category === c.code ? null : c.code)}
            className={`shrink-0 px-3 py-1.5 rounded-full text-[11px] font-semibold ${
              category === c.code
                ? "gradient-wallet text-primary-foreground"
                : "bg-card border border-border text-muted-foreground"
            }`}
          >
            {c.name_fr}
          </button>
        ))}
      </div>

      <p className="text-[11px] text-muted-foreground">
        Catalogue de référence ChopChop — unités et quantités officielles. Prix et commande : à connecter.
      </p>

      {loading ? (
        <LoadingState variant="cards" rows={3} />
      ) : items.length === 0 ? (
        <EmptyState
          icon={Package}
          title="Aucun essentiel trouvé"
          description="Essayez un autre mot ou une autre catégorie."
        />
      ) : (
        <div className="space-y-2">
          {items.map((s) => (
            <button
              key={s.commodity_code}
              onClick={() => getStaple(s.commodity_code).then(setDetail)}
              className="w-full flex items-center gap-3 rounded-2xl bg-card border border-border/60 p-3 text-left active:scale-[0.99] transition-transform"
            >
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                <Package className="w-5 h-5 text-primary" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground truncate">{s.name_fr}</p>
                <p className="text-[11px] text-muted-foreground truncate">
                  {s.category_name_fr}
                  {s.sale_units?.length ? ` · ${s.sale_units.join(" · ")}` : ""}
                </p>
              </div>
              <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
            </button>
          ))}
        </div>
      )}

      {detail && (
        <div className="fixed inset-0 z-50 bg-background/95 overflow-y-auto">
          <div className="max-w-md mx-auto p-4 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-semibold text-foreground">{detail.name_fr}</h2>
              <button onClick={() => setDetail(null)} aria-label="Fermer" className="w-9 h-9 rounded-full bg-card border border-border flex items-center justify-center">
                <X className="w-4 h-4 text-foreground" />
              </button>
            </div>
            <p className="text-xs text-muted-foreground">{detail.category_name_fr}</p>
            {detail.variants.map((v) => (
              <div key={v.variant_code} className="rounded-2xl bg-card border border-border/60 p-3 space-y-2">
                <p className="text-sm font-semibold text-foreground">{v.name_fr}</p>
                {v.grade_note_fr && <p className="text-[11px] text-muted-foreground">{v.grade_note_fr}</p>}
                <div className="space-y-1.5">
                  {v.purchase_options.map((o) => (
                    <div key={o.option_code} className="flex items-center justify-between gap-2 rounded-xl bg-muted/40 px-3 py-2">
                      <div className="min-w-0">
                        <p className="text-xs font-medium text-foreground truncate">{o.label_fr}</p>
                        <p className="text-[10px] text-muted-foreground">{normalizationLabel(o)}</p>
                      </div>
                      <span className="text-[10px] text-muted-foreground shrink-0">
                        {o.min_qty}–{o.max_qty} (pas {o.step_qty})
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
            <p className="text-[11px] text-muted-foreground italic">
              Prix, disponibilité et commande : à connecter.
            </p>
          </div>
        </div>
      )}
    </section>
  );
}
