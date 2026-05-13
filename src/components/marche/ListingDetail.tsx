import { useEffect, useState } from "react";
import { ArrowLeft, MapPin, Heart, Flag, Phone, MessageCircle, Truck, BadgeCheck, ChevronLeft, ChevronRight } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { categoryLabel, formatGNF, timeAgo, type SellerKind } from "@/lib/marche";
import { SellerBadge } from "./SellerBadge";
import { ReportModal } from "./ReportModal";
import { ChatThread } from "./ChatThread";
import { toast } from "@/hooks/use-toast";

interface FullListing {
  id: string;
  seller_id: string;
  kind: SellerKind;
  category: string;
  title: string;
  description: string | null;
  price_gnf: number | null;
  is_negotiable: boolean;
  is_urgent: boolean;
  delivery_available: boolean;
  condition: string | null;
  neighborhood: string | null;
  commune: string | null;
  landmark: string | null;
  created_at: string;
}

export function ListingDetail({ listingId, onBack }: { listingId: string; onBack: () => void }) {
  const [listing, setListing] = useState<FullListing | null>(null);
  const [images, setImages] = useState<string[]>([]);
  const [seller, setSeller] = useState<{ full_name: string | null; phone: string | null } | null>(null);
  const [imgIdx, setImgIdx] = useState(0);
  const [reportOpen, setReportOpen] = useState(false);
  const [saved, setSaved] = useState(false);
  const [selfId, setSelfId] = useState<string | null>(null);
  const [openConv, setOpenConv] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id ?? null;
      if (mounted) setSelfId(uid);

      const { data: l } = await supabase
        .from("marketplace_listings")
        .select("id, seller_id, kind, category, title, description, price_gnf, is_negotiable, is_urgent, delivery_available, condition, neighborhood, commune, landmark, created_at")
        .eq("id", listingId)
        .maybeSingle();
      if (!mounted || !l) return;
      setListing(l as FullListing);

      const { data: imgs } = await supabase
        .from("listing_images")
        .select("url, position")
        .eq("listing_id", listingId)
        .order("position", { ascending: true });
      if (mounted) setImages((imgs ?? []).map((i) => i.url));

      const { data: prof } = await supabase
        .from("profiles")
        .select("full_name, phone")
        .eq("user_id", l.seller_id)
        .maybeSingle();
      if (mounted) setSeller(prof ?? { full_name: null, phone: null });

      if (uid) {
        const { data: sv } = await supabase
          .from("saved_listings")
          .select("listing_id")
          .eq("listing_id", listingId)
          .eq("user_id", uid)
          .maybeSingle();
        if (mounted) setSaved(!!sv);
      }
    })();
    return () => {
      mounted = false;
    };
  }, [listingId]);

  const toggleSave = async () => {
    if (!selfId) {
      toast({ title: "Connexion requise", description: "Connectez-vous pour sauvegarder." });
      return;
    }
    if (saved) {
      await supabase.from("saved_listings").delete().eq("listing_id", listingId).eq("user_id", selfId);
      setSaved(false);
    } else {
      await supabase.from("saved_listings").insert({ listing_id: listingId, user_id: selfId });
      setSaved(true);
    }
  };

  const startChat = async () => {
    if (!listing) return;
    if (!selfId) {
      toast({ title: "Connexion requise", description: "Connectez-vous pour discuter." });
      return;
    }
    if (selfId === listing.seller_id) {
      toast({ title: "Votre annonce", description: "Vous ne pouvez pas vous écrire à vous-même." });
      return;
    }
    const { data: existing } = await supabase
      .from("conversations")
      .select("id")
      .eq("listing_id", listing.id)
      .eq("buyer_id", selfId)
      .maybeSingle();
    if (existing) {
      setOpenConv(existing.id);
      return;
    }
    const { data: created, error } = await supabase
      .from("conversations")
      .insert({ listing_id: listing.id, buyer_id: selfId, seller_id: listing.seller_id })
      .select("id")
      .single();
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    setOpenConv(created.id);
  };

  const requestDelivery = () => {
    toast({
      title: "Livraison CHOP CHOP",
      description: "Le vendeur sera notifié. Un livreur viendra chercher l'article.",
    });
  };

  if (!listing)
    return (
      <div className="max-w-md mx-auto p-6 text-center text-muted-foreground">Chargement…</div>
    );

  const location = [listing.neighborhood, listing.commune, listing.landmark].filter(Boolean).join(" · ") || "Conakry";

  return (
    <div className="max-w-md mx-auto pb-24 bg-background min-h-screen">
      <header className="sticky top-0 z-30 bg-background/90 backdrop-blur flex items-center justify-between px-4 py-3 border-b">
        <button onClick={onBack} className="p-2 -ml-2 rounded-full hover:bg-muted">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex items-center gap-2">
          <button onClick={toggleSave} className="p-2 rounded-full hover:bg-muted">
            <Heart className={`w-5 h-5 ${saved ? "fill-destructive text-destructive" : ""}`} />
          </button>
          <button onClick={() => setReportOpen(true)} className="p-2 rounded-full hover:bg-muted">
            <Flag className="w-5 h-5" />
          </button>
        </div>
      </header>

      {/* Gallery */}
      <div className="relative bg-muted aspect-square">
        {images.length > 0 ? (
          <img src={images[imgIdx]} alt={listing.title} className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-muted-foreground">Aucune photo</div>
        )}
        {images.length > 1 && (
          <>
            <button
              onClick={() => setImgIdx((i) => (i - 1 + images.length) % images.length)}
              className="absolute left-2 top-1/2 -translate-y-1/2 p-2 rounded-full bg-background/80 shadow"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button
              onClick={() => setImgIdx((i) => (i + 1) % images.length)}
              className="absolute right-2 top-1/2 -translate-y-1/2 p-2 rounded-full bg-background/80 shadow"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
            <div className="absolute bottom-2 left-1/2 -translate-x-1/2 flex gap-1">
              {images.map((_, i) => (
                <span key={i} className={`w-1.5 h-1.5 rounded-full ${i === imgIdx ? "bg-white" : "bg-white/50"}`} />
              ))}
            </div>
          </>
        )}
      </div>

      <div className="px-4 py-4 space-y-4">
        <div>
          <h1 className="text-xl font-bold text-foreground">{listing.title}</h1>
          <p className="text-2xl font-bold text-primary mt-1">
            {formatGNF(listing.price_gnf)}
            {listing.is_negotiable && (
              <span className="text-xs font-medium text-muted-foreground ml-2">Négociable</span>
            )}
          </p>
          <div className="flex flex-wrap gap-2 mt-2">
            {listing.is_urgent && (
              <span className="px-2 py-0.5 rounded-full bg-destructive text-destructive-foreground text-xs font-semibold">
                Urgent
              </span>
            )}
            {listing.delivery_available && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-primary text-primary-foreground text-xs font-semibold">
                <Truck className="w-3 h-3" /> Livraison CHOP CHOP
              </span>
            )}
            <span className="px-2 py-0.5 rounded-full bg-muted text-foreground text-xs">
              {categoryLabel(listing.category)}
            </span>
            {listing.condition && (
              <span className="px-2 py-0.5 rounded-full bg-muted text-foreground text-xs">{listing.condition}</span>
            )}
          </div>
          <p className="text-xs text-muted-foreground mt-2">Publié {timeAgo(listing.created_at)}</p>
        </div>

        <div className="flex items-center gap-2 text-sm text-foreground">
          <MapPin className="w-4 h-4 text-primary shrink-0" />
          <span>{location}</span>
        </div>

        {listing.description && (
          <div className="bg-card rounded-2xl p-4 shadow-card">
            <h2 className="font-semibold mb-2">Description</h2>
            <p className="text-sm text-foreground whitespace-pre-wrap">{listing.description}</p>
          </div>
        )}

        {/* Seller card */}
        <div className="bg-card rounded-2xl p-4 shadow-card">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
              <BadgeCheck className="w-6 h-6 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold truncate">{seller?.full_name ?? "Vendeur CHOP CHOP"}</p>
              <div className="mt-0.5">
                <SellerBadge kind={listing.kind} />
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <Button onClick={startChat} className="w-full">
            <MessageCircle className="w-4 h-4 mr-1" /> Message
          </Button>
          {seller?.phone ? (
            <a href={`tel:${seller.phone}`} className="w-full">
              <Button variant="outline" className="w-full">
                <Phone className="w-4 h-4 mr-1" /> Appeler
              </Button>
            </a>
          ) : (
            <Button variant="outline" disabled className="w-full">
              <Phone className="w-4 h-4 mr-1" /> Appeler
            </Button>
          )}
        </div>
        {listing.delivery_available && (
          <Button onClick={requestDelivery} variant="secondary" className="w-full">
            <Truck className="w-4 h-4 mr-1" /> Faire livrer
          </Button>
        )}
      </div>

      <ReportModal listingId={listing.id} open={reportOpen} onOpenChange={setReportOpen} />
      {openConv && selfId && (
        <ChatThread
          conversationId={openConv}
          selfId={selfId}
          peerName={seller?.full_name ?? "Vendeur"}
          listingTitle={listing.title}
          onBack={() => setOpenConv(null)}
        />
      )}
    </div>
  );
}