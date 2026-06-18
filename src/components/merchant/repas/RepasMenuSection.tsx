import { useEffect, useRef, useState } from "react";
import { Plus, Trash2, ImagePlus, Pencil, Loader2 } from "lucide-react";
import { SectionCard } from "../SectionCard";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { toast } from "@/hooks/use-toast";
import {
  createMenuItem,
  deleteMenuItem,
  REPAS_MENU_CATEGORIES,
  updateMenuItem,
  uploadMenuItemPhoto,
} from "@/lib/repas/merchantOps";
import { listMenu } from "@/lib/repas/restaurants";
import type { FoodMenuItem } from "@/lib/repas/types";

interface Props {
  restaurantId: string;
  ownerUserId: string;
}

type Draft = {
  id?: string;
  name: string;
  description: string;
  price: string;
  category: string;
  prep: string;
  is_available: boolean;
  photo_url: string | null;
};

const emptyDraft: Draft = {
  name: "",
  description: "",
  price: "",
  category: REPAS_MENU_CATEGORIES[0],
  prep: "",
  is_available: true,
  photo_url: null,
};

export function RepasMenuSection({ restaurantId, ownerUserId }: Props) {
  const [items, setItems] = useState<FoodMenuItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const reload = async () => {
    setLoading(true);
    try {
      setItems(await listMenu(restaurantId));
    } catch (e) {
      console.warn("[repas] menu load failed", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [restaurantId]);

  const openCreate = () => {
    setDraft(emptyDraft);
    setOpen(true);
  };

  const openEdit = (it: FoodMenuItem) => {
    setDraft({
      id: it.id,
      name: it.name,
      description: it.description ?? "",
      price: String(it.price_gnf ?? ""),
      category: it.category ?? REPAS_MENU_CATEGORIES[0],
      prep: it.prep_time_min != null ? String(it.prep_time_min) : "",
      is_available: it.is_available,
      photo_url: it.photo_url,
    });
    setOpen(true);
  };

  const onPhoto = async (file: File) => {
    setUploading(true);
    try {
      const url = await uploadMenuItemPhoto({
        ownerUserId,
        restaurantId,
        file,
      });
      setDraft((d) => ({ ...d, photo_url: url }));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Téléversement impossible." });
    } finally {
      setUploading(false);
    }
  };

  const save = async () => {
    const price = Number(draft.price.replace(/[^\d]/g, ""));
    if (!draft.name.trim()) {
      toast({ title: "Nom requis", description: "Donnez un nom au plat." });
      return;
    }
    if (!Number.isFinite(price) || price <= 0) {
      toast({ title: "Prix requis", description: "Entrez un prix en GNF." });
      return;
    }
    const prep = draft.prep.trim() ? Number(draft.prep) : null;
    setSaving(true);
    try {
      if (draft.id) {
        await updateMenuItem(draft.id, {
          name: draft.name.trim(),
          description: draft.description.trim() || null,
          price_gnf: price,
          category: draft.category || null,
          prep_time_min: prep,
          is_available: draft.is_available,
          photo_url: draft.photo_url,
        });
      } else {
        await createMenuItem({
          restaurantId,
          name: draft.name.trim(),
          description: draft.description.trim() || null,
          price_gnf: price,
          category: draft.category || null,
          prep_time_min: prep,
          is_available: draft.is_available,
          photo_url: draft.photo_url,
        });
      }
      setOpen(false);
      await reload();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible." });
    } finally {
      setSaving(false);
    }
  };

  const remove = async (it: FoodMenuItem) => {
    if (!confirm(`Supprimer « ${it.name} » ?`)) return;
    try {
      await deleteMenuItem(it.id);
      setItems((prev) => prev.filter((x) => x.id !== it.id));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Suppression impossible." });
    }
  };

  const toggle = async (it: FoodMenuItem, v: boolean) => {
    setItems((prev) => prev.map((x) => (x.id === it.id ? { ...x, is_available: v } : x)));
    try {
      await updateMenuItem(it.id, { is_available: v });
    } catch (e: any) {
      setItems((prev) => prev.map((x) => (x.id === it.id ? { ...x, is_available: !v } : x)));
      toast({ title: "Erreur", description: e?.message ?? "Action impossible." });
    }
  };

  return (
    <SectionCard
      title="Menu"
      hint="Vos plats — ajoutez, modifiez, masquez en cas de rupture."
      action={
        <Button size="sm" onClick={openCreate} className="rounded-full">
          <Plus className="w-4 h-4 mr-1" /> Ajouter
        </Button>
      }
    >
      {loading ? (
        <p className="text-sm text-muted-foreground">Chargement…</p>
      ) : items.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border/60 p-4 text-center">
          <p className="text-sm font-medium text-foreground">Aucun plat pour le moment.</p>
          <p className="text-xs text-muted-foreground mt-1">
            Ajoutez votre premier plat pour que les clients puissent commander.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {items.map((it) => (
            <div
              key={it.id}
              className="flex gap-3 rounded-xl bg-muted/40 border border-border/50 p-2.5"
            >
              <div className="w-14 h-14 rounded-lg bg-muted overflow-hidden shrink-0 flex items-center justify-center">
                {it.photo_url ? (
                  <img
                    src={it.photo_url}
                    alt=""
                    loading="lazy"
                    onError={(e) => {
                      (e.currentTarget as HTMLImageElement).style.display = "none";
                    }}
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <ImagePlus className="w-5 h-5 text-muted-foreground" />
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-semibold text-foreground truncate">{it.name}</p>
                  <Switch
                    checked={!!it.is_available}
                    onCheckedChange={(v) => toggle(it, v)}
                    aria-label="Disponible"
                  />
                </div>
                <p className="text-xs text-muted-foreground">
                  {Number(it.price_gnf).toLocaleString("fr-FR")} GNF
                  {it.category ? ` · ${it.category}` : ""}
                </p>
                <div className="flex items-center gap-1 mt-1">
                  <button
                    onClick={() => openEdit(it)}
                    className="text-[11px] inline-flex items-center gap-1 text-foreground/80 hover:text-foreground"
                  >
                    <Pencil className="w-3 h-3" /> Modifier
                  </button>
                  <span className="text-[11px] text-muted-foreground">·</span>
                  <button
                    onClick={() => remove(it)}
                    className="text-[11px] inline-flex items-center gap-1 text-destructive hover:text-destructive/80"
                  >
                    <Trash2 className="w-3 h-3" /> Supprimer
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="bottom" className="max-w-md mx-auto rounded-t-3xl">
          <SheetHeader>
            <SheetTitle>{draft.id ? "Modifier le plat" : "Nouveau plat"}</SheetTitle>
          </SheetHeader>
          <div className="space-y-3 mt-4">
            <div className="flex items-center gap-3">
              <button
                onClick={() => fileRef.current?.click()}
                className="w-20 h-20 rounded-xl border border-dashed border-border/70 bg-muted/40 flex items-center justify-center overflow-hidden"
              >
                {uploading ? (
                  <Loader2 className="w-5 h-5 animate-spin text-muted-foreground" />
                ) : draft.photo_url ? (
                  <img src={draft.photo_url} alt="" className="w-full h-full object-cover" />
                ) : (
                  <ImagePlus className="w-6 h-6 text-muted-foreground" />
                )}
              </button>
              <div className="text-xs text-muted-foreground">
                Photo du plat (JPEG/PNG/WebP, 5 Mo max).
                {draft.photo_url && (
                  <button
                    onClick={() => setDraft((d) => ({ ...d, photo_url: null }))}
                    className="block mt-1 text-destructive"
                  >
                    Retirer la photo
                  </button>
                )}
              </div>
              <input
                ref={fileRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) onPhoto(f);
                  e.currentTarget.value = "";
                }}
              />
            </div>
            <div>
              <Label className="text-xs">Nom</Label>
              <Input
                value={draft.name}
                onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))}
                placeholder="Riz gras au poulet"
                maxLength={80}
              />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label className="text-xs">Prix (GNF)</Label>
                <Input
                  inputMode="numeric"
                  value={draft.price}
                  onChange={(e) =>
                    setDraft((d) => ({ ...d, price: e.target.value.replace(/[^\d]/g, "") }))
                  }
                  placeholder="35000"
                />
              </div>
              <div>
                <Label className="text-xs">Préparation (min)</Label>
                <Input
                  inputMode="numeric"
                  value={draft.prep}
                  onChange={(e) =>
                    setDraft((d) => ({ ...d, prep: e.target.value.replace(/[^\d]/g, "") }))
                  }
                  placeholder="20"
                />
              </div>
            </div>
            <div>
              <Label className="text-xs">Catégorie</Label>
              <select
                value={draft.category}
                onChange={(e) => setDraft((d) => ({ ...d, category: e.target.value }))}
                className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
              >
                {REPAS_MENU_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <Label className="text-xs">Description</Label>
              <Textarea
                value={draft.description}
                onChange={(e) => setDraft((d) => ({ ...d, description: e.target.value }))}
                placeholder="Ingrédients, portion…"
                maxLength={400}
                rows={3}
              />
            </div>
            <div className="flex items-center justify-between rounded-xl bg-muted/40 px-3 py-2">
              <span className="text-sm font-medium">Disponible</span>
              <Switch
                checked={draft.is_available}
                onCheckedChange={(v) => setDraft((d) => ({ ...d, is_available: v }))}
              />
            </div>
            <Button onClick={save} disabled={saving || uploading} className="w-full">
              {saving ? "Enregistrement…" : draft.id ? "Enregistrer" : "Ajouter au menu"}
            </Button>
          </div>
        </SheetContent>
      </Sheet>
    </SectionCard>
  );
}