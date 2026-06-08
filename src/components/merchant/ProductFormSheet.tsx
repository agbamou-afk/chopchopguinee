import { useEffect, useRef, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Camera, ImagePlus, Loader2 } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import {
  PRODUCT_CATEGORIES,
  createProduct,
  updateProduct,
  uploadProductImage,
  getProductImages,
  type MerchantProduct,
} from "@/lib/marche/products";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  userId: string;
  storeId: string | null;
  canPublish: boolean; // approved merchant?
  pendingNote?: string | null;
  product?: MerchantProduct | null; // edit mode
  onSaved?: (p: MerchantProduct) => void;
  fastAdd?: boolean;
  onToggleFastAdd?: (v: boolean) => void;
  defaultCategory?: string;
}

export function ProductFormSheet({
  open, onOpenChange, userId, storeId, canPublish, pendingNote,
  product, onSaved, fastAdd, onToggleFastAdd, defaultCategory,
}: Props) {
  const isEdit = !!product;
  const [title, setTitle] = useState("");
  const [price, setPrice] = useState<string>("");
  const [qty, setQty] = useState<string>("1");
  const [category, setCategory] = useState(defaultCategory || PRODUCT_CATEGORIES[0]);
  const [barcode, setBarcode] = useState("");
  const [description, setDescription] = useState("");
  const [imageUrls, setImageUrls] = useState<string[]>([]);
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    if (product) {
      setTitle(product.title);
      setPrice(product.price_gnf ? String(product.price_gnf) : "");
      setQty(String(product.quantity_in_stock ?? 0));
      setCategory(product.category || PRODUCT_CATEGORIES[0]);
      setBarcode(product.barcode || "");
      setDescription(product.description || "");
      getProductImages(product.id).then(setImageUrls).catch(() => setImageUrls([]));
    } else {
      setTitle("");
      setPrice("");
      setQty("1");
      setCategory(defaultCategory || PRODUCT_CATEGORIES[0]);
      setBarcode("");
      setDescription("");
      setImageUrls([]);
    }
    setPendingFile(null);
    setPreviewUrl(null);
  }, [open, product, defaultCategory]);

  const onPickFile = (f: File | null) => {
    if (!f) return;
    setPendingFile(f);
    const url = URL.createObjectURL(f);
    setPreviewUrl(url);
  };

  const save = async (publish: boolean) => {
    if (!title.trim()) {
      toast({ title: "Nom requis", description: "Ajoutez un nom de produit." });
      return;
    }
    setSaving(true);
    try {
      let row: MerchantProduct;
      if (isEdit && product) {
        await updateProduct(product.id, {
          title: title.trim(),
          category,
          price_gnf: price ? Number(price) : null,
          quantity_in_stock: qty ? Number(qty) : 0,
          barcode: barcode.trim() || null,
          description: description.trim() || null,
          ...(publish && canPublish ? { status: "active", visibility: "public" } : {}),
        });
        row = { ...product, title, category, price_gnf: price ? Number(price) : null, quantity_in_stock: qty ? Number(qty) : 0, barcode, description };
      } else {
        row = await createProduct({
          sellerId: userId,
          storeId,
          title: title.trim(),
          category,
          price_gnf: price ? Number(price) : null,
          quantity_in_stock: qty ? Number(qty) : 0,
          barcode: barcode.trim() || null,
          description: description.trim() || null,
          publish: publish && canPublish,
        });
      }
      if (pendingFile) {
        try {
          await uploadProductImage({
            userId,
            listingId: row.id,
            file: pendingFile,
            position: imageUrls.length,
          });
        } catch (e: any) {
          toast({ title: "Photo non envoyée", description: e?.message ?? "Réessayez." });
        }
      }
      toast({ title: isEdit ? "Produit mis à jour" : "Produit enregistré" });
      onSaved?.(row);
      if (fastAdd && !isEdit) {
        // keep category, reset rest
        setTitle("");
        setPrice("");
        setQty("1");
        setBarcode("");
        setDescription("");
        setPendingFile(null);
        setPreviewUrl(null);
      } else {
        onOpenChange(false);
      }
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="max-h-[95vh] overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{isEdit ? "Modifier le produit" : "Ajouter un produit"}</SheetTitle>
        </SheetHeader>

        {pendingNote && (
          <div className="mt-3 rounded-xl bg-amber-500/10 border border-amber-500/40 p-3 text-xs text-amber-900 dark:text-amber-200">
            {pendingNote}
          </div>
        )}

        <div className="mt-4 space-y-4">
          <div>
            <Label className="text-sm">Photo du produit</Label>
            <div className="mt-2 flex items-center gap-3">
              <div className="w-24 h-24 rounded-xl border border-border/60 bg-muted/40 flex items-center justify-center overflow-hidden">
                {previewUrl ? (
                  <img src={previewUrl} alt="" className="w-full h-full object-cover" />
                ) : imageUrls[0] ? (
                  <img src={imageUrls[0]} alt="" className="w-full h-full object-cover" />
                ) : (
                  <ImagePlus className="w-6 h-6 text-muted-foreground" />
                )}
              </div>
              <div className="flex flex-col gap-2">
                <Button type="button" size="sm" variant="outline" onClick={() => fileRef.current?.click()}>
                  <Camera className="w-4 h-4 mr-1" /> Prendre / choisir
                </Button>
                <span className="text-[10px] text-muted-foreground">Suppression d'arrière-plan — bientôt</span>
              </div>
              <input
                ref={fileRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                capture="environment"
                className="hidden"
                onChange={(e) => onPickFile(e.target.files?.[0] ?? null)}
              />
            </div>
          </div>

          <div>
            <Label htmlFor="p-name">Nom du produit</Label>
            <Input id="p-name" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Ex. Riz parfumé 5kg" />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="p-price">Prix en GNF</Label>
              <Input id="p-price" type="number" inputMode="numeric" min={0} value={price} onChange={(e) => setPrice(e.target.value)} placeholder="0" />
            </div>
            <div>
              <Label htmlFor="p-qty">Quantité en stock</Label>
              <Input id="p-qty" type="number" inputMode="numeric" min={0} value={qty} onChange={(e) => setQty(e.target.value)} placeholder="0" />
            </div>
          </div>

          <div>
            <Label htmlFor="p-cat">Catégorie</Label>
            <select
              id="p-cat"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="mt-1 w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
            >
              {PRODUCT_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>

          <div>
            <Label htmlFor="p-bar">Code-barres ou référence</Label>
            <Input id="p-bar" value={barcode} onChange={(e) => setBarcode(e.target.value)} placeholder="Scanner bientôt disponible" />
          </div>

          <div>
            <Label htmlFor="p-desc">Description (optionnel)</Label>
            <Textarea id="p-desc" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>

          {!isEdit && onToggleFastAdd && (
            <label className="flex items-center gap-2 text-xs text-muted-foreground">
              <input type="checkbox" checked={!!fastAdd} onChange={(e) => onToggleFastAdd(e.target.checked)} />
              Mode ajout rapide (garder la catégorie, réinitialiser le reste)
            </label>
          )}

          <div className="flex gap-2 pt-2 sticky bottom-0 bg-background pb-2">
            <Button variant="outline" className="flex-1" disabled={saving} onClick={() => save(false)}>
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Enregistrer le brouillon"}
            </Button>
            {canPublish && (
              <Button className="flex-1" disabled={saving} onClick={() => save(true)}>
                {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Publier"}
              </Button>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}