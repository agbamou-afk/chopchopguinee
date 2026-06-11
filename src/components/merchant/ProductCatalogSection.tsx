import { useEffect, useMemo, useState } from "react";
import { SectionCard } from "./SectionCard";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/hooks/use-toast";
import { Plus, Minus, Edit2, Archive, PackageX, Upload, Eye, EyeOff } from "lucide-react";
import {
  listOwnProducts,
  adjustStock,
  setOutOfStock,
  archiveProduct,
  publishProduct,
  unpublishProduct,
  productStatusLabel,
  type MerchantProduct,
} from "@/lib/marche/products";
import { ProductFormSheet } from "./ProductFormSheet";

interface Props {
  userId: string;
  storeId: string | null;
  approved: boolean;
}

type FilterKey = "all" | "draft" | "active" | "oos" | "archived";

export function ProductCatalogSection({ userId, storeId, approved }: Props) {
  const [items, setItems] = useState<MerchantProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<MerchantProduct | null>(null);
  const [filter, setFilter] = useState<FilterKey>("all");
  const [q, setQ] = useState("");
  const [fastAdd, setFastAdd] = useState(false);

  const refresh = async () => {
    setLoading(true);
    try {
      setItems(await listOwnProducts(userId));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Chargement impossible" });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { refresh(); /* eslint-disable-next-line */ }, [userId]);

  const filtered = useMemo(() => {
    let out = items;
    if (filter === "draft") out = out.filter((p) => p.status === "paused");
    if (filter === "active") out = out.filter((p) => p.status === "active" && (p.quantity_in_stock ?? 0) > 0 && p.visibility === "public");
    if (filter === "oos") out = out.filter((p) => (p.quantity_in_stock ?? 0) <= 0 && p.status !== "removed");
    if (filter === "archived") out = out.filter((p) => p.status === "removed");
    const qq = q.trim().toLowerCase();
    if (qq) out = out.filter((p) =>
      p.title.toLowerCase().includes(qq) || (p.barcode ?? "").toLowerCase().includes(qq),
    );
    return out;
  }, [items, filter, q]);

  const counts = useMemo(() => {
    const c = { all: items.length, active: 0, draft: 0, oos: 0, archived: 0 };
    for (const p of items) {
      if (p.status === "removed") c.archived += 1;
      else if ((p.quantity_in_stock ?? 0) <= 0) c.oos += 1;
      else if (p.status === "active" && p.visibility === "public") c.active += 1;
      else c.draft += 1;
    }
    return c;
  }, [items]);

  const onStock = async (id: string, delta: number) => {
    try {
      const next = await adjustStock(id, delta);
      setItems((prev) => prev.map((p) => (p.id === id ? { ...p, quantity_in_stock: next } : p)));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Stock non mis à jour" });
    }
  };

  const onOOS = async (id: string) => {
    try {
      await setOutOfStock(id);
      setItems((prev) => prev.map((p) => (p.id === id ? { ...p, quantity_in_stock: 0 } : p)));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  const onArchive = async (id: string) => {
    if (!confirm("Archiver ce produit ? Il ne sera plus visible.")) return;
    try {
      await archiveProduct(id);
      setItems((prev) => prev.map((p) => (p.id === id ? { ...p, status: "removed", visibility: "private" } : p)));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  const onTogglePublish = async (p: MerchantProduct) => {
    try {
      if (p.status === "active" && p.visibility === "public") {
        await unpublishProduct(p.id);
        setItems((prev) => prev.map((x) => (x.id === p.id ? { ...x, status: "paused", visibility: "private" } : x)));
      } else {
        await publishProduct(p.id);
        // refresh from server because trigger may force private if store not approved
        await refresh();
      }
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  const pendingNote = !approved
    ? "Votre catalogue est privé pendant la vérification. Vous pouvez préparer vos produits maintenant."
    : null;
  const approvedNote = approved
    ? "Vos produits publiés sont visibles dans CHOP Marché."
    : null;

  return (
    <SectionCard title="Mon inventaire" hint="Gérez votre stock, prix et visibilité">
      {pendingNote && (
        <div className="mb-3 rounded-xl bg-amber-500/10 border border-amber-500/40 p-3 text-xs text-amber-900 dark:text-amber-200">
          {pendingNote}
        </div>
      )}
      {approvedNote && (
        <div className="mb-3 rounded-xl bg-emerald-500/10 border border-emerald-500/30 p-3 text-xs text-emerald-900 dark:text-emerald-200">
          {approvedNote}
        </div>
      )}

      {/* Inventory summary chips */}
      <div className="grid grid-cols-4 gap-2 mb-3">
        {([
          ["active", "Actifs", counts.active, "text-emerald-700"],
          ["draft", "Privés", counts.draft, "text-muted-foreground"],
          ["oos", "Rupture", counts.oos, "text-amber-700"],
          ["archived", "Archivés", counts.archived, "text-muted-foreground"],
        ] as [FilterKey, string, number, string][]).map(([k, label, n, tone]) => (
          <button
            key={k}
            onClick={() => setFilter(k)}
            className={`rounded-xl border p-2 text-left transition ${
              filter === k ? "border-primary bg-primary/5" : "border-border/60 bg-card"
            }`}
          >
            <div className={`text-base font-extrabold ${tone}`}>{n}</div>
            <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
          </button>
        ))}
      </div>

      <div className="flex gap-2 mb-3">
        <Button size="sm" className="flex-1" onClick={() => { setEditing(null); setOpen(true); }}>
          <Upload className="w-4 h-4 mr-1" /> Ajouter un produit
        </Button>
      </div>

      <Input
        placeholder="Rechercher par nom ou code-barres"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        className="mb-2"
      />

      <div className="flex gap-1 mb-3 flex-wrap">
        {([
          ["all", "Tous"],
          ["draft", "Brouillons"],
          ["active", "Publiés"],
          ["oos", "Rupture"],
          ["archived", "Archivés"],
        ] as [FilterKey, string][]).map(([k, l]) => (
          <button
            key={k}
            onClick={() => setFilter(k)}
            className={`px-2.5 py-1 rounded-full text-xs border ${
              filter === k
                ? "bg-primary text-primary-foreground border-primary"
                : "bg-card border-border/60 text-muted-foreground"
            }`}
          >
            {l}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Chargement…</p>
      ) : items.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Votre catalogue est vide. Ajoutez votre premier produit.
        </p>
      ) : filtered.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucun produit dans ce filtre.</p>
      ) : (
        <div className="space-y-2">
          {filtered.map((p) => {
            const label = productStatusLabel(p);
            const isPub = p.status === "active" && p.visibility === "public";
            return (
              <div key={p.id} className="rounded-xl bg-muted/40 border border-border/50 p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-semibold text-foreground truncate">{p.title}</p>
                    <p className="text-xs text-muted-foreground">
                      {p.price_gnf ? `${Number(p.price_gnf).toLocaleString("fr-FR")} GNF` : "—"} · {p.category}
                    </p>
                    <div className="mt-1 flex gap-2 items-center">
                      <span className="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-card border border-border/60 text-muted-foreground">
                        {label}
                      </span>
                      <span className="text-[10px] text-muted-foreground">
                        Stock: {p.quantity_in_stock ?? 0}
                      </span>
                    </div>
                    {p.status !== "removed" && (
                      <p className={`mt-1 text-[10px] font-medium ${
                        p.status === "active" && p.visibility === "public" && (p.quantity_in_stock ?? 0) > 0
                          ? "text-emerald-700"
                          : "text-muted-foreground"
                      }`}>
                        {p.status === "active" && p.visibility === "public" && (p.quantity_in_stock ?? 0) > 0
                          ? "Visible sur CHOP Marché"
                          : "Privé — non visible aux clients"}
                      </p>
                    )}
                  </div>
                </div>
                <div className="flex flex-wrap gap-1 mt-3">
                  <Button size="sm" variant="outline" onClick={() => onStock(p.id, 1)}>
                    <Plus className="w-3 h-3" />
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => onStock(p.id, -1)}>
                    <Minus className="w-3 h-3" />
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => onOOS(p.id)}>
                    <PackageX className="w-3 h-3 mr-1" /> Rupture
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => { setEditing(p); setOpen(true); }}>
                    <Edit2 className="w-3 h-3 mr-1" /> Modifier
                  </Button>
                  {approved && p.status !== "removed" && (
                    <Button size="sm" variant="outline" onClick={() => onTogglePublish(p)}>
                      {isPub ? <><EyeOff className="w-3 h-3 mr-1" /> Dépublier</> : <><Eye className="w-3 h-3 mr-1" /> Publier</>}
                    </Button>
                  )}
                  {p.status !== "removed" && (
                    <Button size="sm" variant="outline" onClick={() => onArchive(p.id)}>
                      <Archive className="w-3 h-3 mr-1" /> Archiver
                    </Button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <ProductFormSheet
        open={open}
        onOpenChange={setOpen}
        userId={userId}
        storeId={storeId}
        canPublish={approved}
        pendingNote={pendingNote}
        product={editing}
        fastAdd={fastAdd}
        onToggleFastAdd={setFastAdd}
        onSaved={() => { refresh(); }}
      />
    </SectionCard>
  );
}