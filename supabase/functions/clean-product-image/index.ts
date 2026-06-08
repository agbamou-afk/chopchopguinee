// CHOPCHOP — Marché product image cleaning (background removal) v1.
// Validates merchant/admin ownership, downloads original image from storage,
// asks Lovable AI Gateway (Gemini image edit) to remove the background, then
// stores the cleaned PNG as a separate listing_images row.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const BUCKET = "marche-listings";
const GATEWAY = "https://ai.gateway.lovable.dev/v1/chat/completions";
const MODEL = "google/gemini-2.5-flash-image-preview";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST")
    return json(405, { ok: false, code: "METHOD_NOT_ALLOWED", error: "Méthode non autorisée." });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const LOVABLE_KEY = Deno.env.get("LOVABLE_API_KEY");

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json(401, { ok: false, code: "AUTH_REQUIRED", error: "Connexion requise." });
  }

  // Caller identity
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return json(401, { ok: false, code: "AUTH_REQUIRED", error: "Connexion requise." });
  }
  const userId = userData.user.id;

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* ignore */ }
  const listingId = String(body.listing_id ?? "");
  const imageId = body.image_id ? String(body.image_id) : null;
  const setPrimary = body.set_primary !== false;
  if (!listingId) {
    return json(400, { ok: false, code: "BAD_INPUT", error: "Identifiant manquant." });
  }

  if (!LOVABLE_KEY) {
    console.error("clean-product-image: LOVABLE_API_KEY not configured");
    return json(503, {
      ok: false,
      code: "PROVIDER_NOT_CONFIGURED",
      error: "Nettoyage d'image indisponible — configuration requise.",
    });
  }

  // Authorize: must own the listing or be admin
  const { data: listing, error: lErr } = await admin
    .from("marketplace_listings")
    .select("id, seller_id")
    .eq("id", listingId)
    .maybeSingle();
  if (lErr || !listing) {
    return json(404, { ok: false, code: "LISTING_NOT_FOUND", error: "Produit introuvable." });
  }
  let isAdmin = false;
  if (listing.seller_id !== userId) {
    const { data: roleRow } = await admin
      .from("user_roles").select("role").eq("user_id", userId).eq("role", "admin").maybeSingle();
    isAdmin = !!roleRow;
    if (!isAdmin) {
      return json(403, { ok: false, code: "FORBIDDEN", error: "Action non autorisée." });
    }
  }

  // Find source image (most recent original if not provided)
  let srcQuery = admin
    .from("listing_images")
    .select("id, url, image_type, listing_id")
    .eq("listing_id", listingId);
  if (imageId) srcQuery = srcQuery.eq("id", imageId);
  else srcQuery = srcQuery.eq("image_type", "original").order("created_at", { ascending: false }).limit(1);
  const { data: srcRows, error: sErr } = await srcQuery;
  if (sErr || !srcRows || srcRows.length === 0) {
    return json(404, { ok: false, code: "IMAGE_NOT_FOUND", error: "Image source introuvable." });
  }
  const src = srcRows[0] as { id: string; url: string };

  // Extract storage path from URL
  const marker = `/object/public/${BUCKET}/`;
  const idx = src.url.indexOf(marker);
  if (idx === -1) {
    return json(400, { ok: false, code: "BAD_SOURCE", error: "Source d'image invalide." });
  }
  const srcPath = src.url.slice(idx + marker.length);

  // Download original
  const { data: blob, error: dErr } = await admin.storage.from(BUCKET).download(srcPath);
  if (dErr || !blob) {
    console.error("clean-product-image: download failed", dErr?.message);
    return json(500, { ok: false, code: "IMAGE_CLEANING_FAILED", error: "Impossible de nettoyer l'image pour le moment." });
  }
  const ab = await blob.arrayBuffer();
  const b64 = btoa(String.fromCharCode(...new Uint8Array(ab)));
  const dataUrl = `data:${blob.type || "image/jpeg"};base64,${b64}`;

  // Call gateway
  let cleanedDataUrl: string | null = null;
  try {
    const aiResp = await fetch(GATEWAY, {
      method: "POST",
      headers: { Authorization: `Bearer ${LOVABLE_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        modalities: ["image", "text"],
        messages: [{
          role: "user",
          content: [
            { type: "text", text: "Remove the background of this product photo. Output a clean PNG with a solid white studio background, well-lit, centered, marketplace-ready. Keep the product exactly as-is." },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        }],
      }),
    });
    if (!aiResp.ok) {
      const t = await aiResp.text().catch(() => "");
      console.error("clean-product-image: gateway", aiResp.status, t.slice(0, 200));
      const code = aiResp.status === 429 ? "RATE_LIMITED" : aiResp.status === 402 ? "PAYMENT_REQUIRED" : "IMAGE_CLEANING_FAILED";
      return json(502, { ok: false, code, error: "Impossible de nettoyer l'image pour le moment." });
    }
    const data = await aiResp.json();
    const images = data?.choices?.[0]?.message?.images;
    cleanedDataUrl = images?.[0]?.image_url?.url ?? null;
  } catch (e) {
    console.error("clean-product-image: gateway exception", (e as Error).message);
    return json(502, { ok: false, code: "IMAGE_CLEANING_FAILED", error: "Impossible de nettoyer l'image pour le moment." });
  }

  if (!cleanedDataUrl || !cleanedDataUrl.startsWith("data:")) {
    return json(502, { ok: false, code: "IMAGE_CLEANING_FAILED", error: "Impossible de nettoyer l'image pour le moment." });
  }

  // Decode the cleaned image data URL
  const commaIdx = cleanedDataUrl.indexOf(",");
  const meta = cleanedDataUrl.slice(5, commaIdx); // e.g. image/png;base64
  const contentType = meta.split(";")[0] || "image/png";
  const b64Out = cleanedDataUrl.slice(commaIdx + 1);
  const binStr = atob(b64Out);
  const bytes = new Uint8Array(binStr.length);
  for (let i = 0; i < binStr.length; i++) bytes[i] = binStr.charCodeAt(i);

  const cleanedPath = `${listing.seller_id}/${listingId}/cleaned-${crypto.randomUUID()}.png`;
  const { error: upErr } = await admin.storage.from(BUCKET).upload(cleanedPath, bytes, {
    contentType,
    upsert: false,
  });
  if (upErr) {
    console.error("clean-product-image: upload failed", upErr.message);
    return json(500, { ok: false, code: "IMAGE_CLEANING_FAILED", error: "Impossible de nettoyer l'image pour le moment." });
  }
  const { data: pub } = admin.storage.from(BUCKET).getPublicUrl(cleanedPath);
  const cleanedUrl = pub.publicUrl;

  // Insert listing_images row
  const { data: ins, error: iErr } = await admin
    .from("listing_images")
    .insert({
      listing_id: listingId,
      url: cleanedUrl,
      position: 0,
      image_type: "cleaned",
      source_image_id: src.id,
      processing_status: "ready",
      is_primary: setPrimary,
    })
    .select("id, url")
    .single();
  if (iErr || !ins) {
    console.error("clean-product-image: insert failed", iErr?.message);
    return json(500, { ok: false, code: "IMAGE_CLEANING_FAILED", error: "Impossible de nettoyer l'image pour le moment." });
  }

  return json(200, {
    ok: true,
    image_id: ins.id,
    url: ins.url,
    source_image_id: src.id,
    image_type: "cleaned",
  });
});