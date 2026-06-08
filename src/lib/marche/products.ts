import { supabase } from "@/integrations/supabase/client";

export type ProductStatus = "active" | "paused" | "removed" | "sold";
export type ProductVisibility = "public" | "private";

export interface MerchantProduct {
  id: string;
  seller_id: string;
  store_id: string | null;
  title: string;
  description: string | null;
  category: string;
  price_gnf: number | null;
  quantity_in_stock: number | null;
  barcode: string | null;
  status: ProductStatus;
  visibility: ProductVisibility;
  photo_count: number;
  availability: string;
  created_at: string;
  updated_at: string;
}

const BUCKET = "marche-listings";
const MAX_BYTES = 5 * 1024 * 1024;
const ALLOWED = ["image/jpeg", "image/png", "image/webp"];

export const PRODUCT_CATEGORIES = [
  "Alimentation",
  "Boissons",
  "Mode",
  "Beauté",
  "Maison",
  "Électronique",
  "Bébé & Enfant",
  "Santé",
  "Autre",
];

export async function listOwnProducts(sellerId: string): Promise<MerchantProduct[]> {
  const { data, error } = await (supabase as any)
    .from("marketplace_listings")
    .select("*")
    .eq("seller_id", sellerId)
    .eq("kind", "merchant")
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw error;
  return (data ?? []) as MerchantProduct[];
}

export async function listStoreProducts(storeId: string): Promise<MerchantProduct[]> {
  const { data, error } = await (supabase as any)
    .from("marketplace_listings")
    .select("*")
    .eq("store_id", storeId)
    .eq("kind", "merchant")
    .order("created_at", { ascending: false })
    .limit(500);
  if (error) throw error;
  return (data ?? []) as MerchantProduct[];
}

export async function getProductImages(listingId: string): Promise<string[]> {
  const { data, error } = await (supabase as any)
    .from("listing_images")
    .select("url")
    .eq("listing_id", listingId)
    .order("position", { ascending: true });
  if (error) throw error;
  return ((data ?? []) as { url: string }[]).map((r) => r.url);
}

export interface CreateProductInput {
  sellerId: string;
  storeId: string | null;
  title: string;
  category: string;
  price_gnf: number | null;
  quantity_in_stock: number | null;
  barcode: string | null;
  description: string | null;
  publish: boolean; // requested public/active
}

export async function createProduct(input: CreateProductInput): Promise<MerchantProduct> {
  const status: ProductStatus = input.publish ? "active" : "paused";
  const visibility: ProductVisibility = input.publish ? "public" : "private";
  const payload = {
    seller_id: input.sellerId,
    store_id: input.storeId,
    kind: "merchant",
    category: input.category || "Autre",
    title: input.title.trim(),
    description: input.description?.trim() || null,
    price_gnf: input.price_gnf,
    quantity_in_stock: input.quantity_in_stock,
    barcode: input.barcode?.trim() || null,
    status,
    visibility,
  };
  const { data, error } = await (supabase as any)
    .from("marketplace_listings")
    .insert(payload)
    .select("*")
    .single();
  if (error) throw error;
  return data as MerchantProduct;
}

export interface UpdateProductInput {
  title?: string;
  category?: string;
  price_gnf?: number | null;
  quantity_in_stock?: number | null;
  barcode?: string | null;
  description?: string | null;
  status?: ProductStatus;
  visibility?: ProductVisibility;
}

export async function updateProduct(id: string, patch: UpdateProductInput): Promise<void> {
  const { error } = await (supabase as any)
    .from("marketplace_listings")
    .update(patch)
    .eq("id", id);
  if (error) throw error;
}

export async function adjustStock(id: string, delta: number): Promise<number> {
  const { data: cur, error: e0 } = await (supabase as any)
    .from("marketplace_listings")
    .select("quantity_in_stock")
    .eq("id", id)
    .maybeSingle();
  if (e0) throw e0;
  const next = Math.max(0, ((cur?.quantity_in_stock as number | null) ?? 0) + delta);
  const { error } = await (supabase as any)
    .from("marketplace_listings")
    .update({ quantity_in_stock: next })
    .eq("id", id);
  if (error) throw error;
  return next;
}

export async function setOutOfStock(id: string): Promise<void> {
  const { error } = await (supabase as any)
    .from("marketplace_listings")
    .update({ quantity_in_stock: 0 })
    .eq("id", id);
  if (error) throw error;
}

export async function archiveProduct(id: string): Promise<void> {
  await updateProduct(id, { status: "removed", visibility: "private" });
}

export async function publishProduct(id: string): Promise<void> {
  await updateProduct(id, { status: "active", visibility: "public" });
}

export async function unpublishProduct(id: string): Promise<void> {
  await updateProduct(id, { status: "paused", visibility: "private" });
}

export async function uploadProductImage(opts: {
  userId: string;
  listingId: string;
  file: File;
  position?: number;
}): Promise<string> {
  const { userId, listingId, file } = opts;
  if (!ALLOWED.includes(file.type)) {
    throw new Error("Format d'image non supporté.");
  }
  if (file.size > MAX_BYTES) {
    throw new Error("Image trop lourde.");
  }
  const ext = (file.name.split(".").pop() || "jpg").toLowerCase();
  const path = `${userId}/${listingId}/${crypto.randomUUID()}.${ext}`;
  const { error: upErr } = await (supabase as any).storage
    .from(BUCKET)
    .upload(path, file, { contentType: file.type, upsert: false });
  if (upErr) throw new Error("Impossible d'envoyer la photo.");
  const { data: pub } = (supabase as any).storage.from(BUCKET).getPublicUrl(path);
  const url = pub?.publicUrl as string;
  const { error: insErr } = await (supabase as any)
    .from("listing_images")
    .insert({ listing_id: listingId, url, position: opts.position ?? 0 });
  if (insErr) throw insErr;
  return url;
}

export async function deleteProductImage(imageId: string): Promise<void> {
  const { error } = await (supabase as any)
    .from("listing_images")
    .delete()
    .eq("id", imageId);
  if (error) throw error;
}

export function productStatusLabel(p: Pick<MerchantProduct, "status" | "visibility" | "quantity_in_stock">): string {
  if (p.status === "removed") return "Archivé";
  if ((p.quantity_in_stock ?? 0) <= 0) return "Rupture";
  if (p.status === "active" && p.visibility === "public") return "Publié";
  if (p.status === "paused") return "Brouillon";
  return "Privé";
}