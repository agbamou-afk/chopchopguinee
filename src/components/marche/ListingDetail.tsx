import { useEffect, useState } from "react";
import { ArrowLeft, MapPin, Heart, Flag, Phone, MessageCircle, Truck, BadgeCheck, ChevronLeft, ChevronRight, Eye } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { categoryLabel, formatGNF, timeAgo, isListingComplete, type SellerKind, type FulfillmentId } from "@/lib/marche";
import { availabilityLabel } from "@/lib/marche";
import { SellerBadge } from "./SellerBadge";
import {
  SellerTrustChips,
  AvailabilityChip,
  FulfillmentChips,
  CompleteListingChip,
} from "./TrustChips";
import { ReportModal } from "./ReportModal";
import { ChatThread } from "./ChatThread";
import { toast } from "@/hooks/use-toast";
import { useAuthGuard } from "@/hooks/useAuthGuard";
import { incrementListingMetric, getListingMetrics, getStoreById, type MerchantStore } from "@/lib/marche/stores";
import {
  createInterest,
  countInterestsByListing,
  type InterestKind,
} from "@/lib/marche/interests";
import { CalendarCheck, PackageSearch } from "lucide-react";
import { Tag } from "lucide-react";
import { OfferSheet } from "./OfferSheet";
import {
  getMyOfferForListing,
  withdrawOffer,
  offerStatusLabel,
  type MarketplaceOffer,
} from "@/lib/marche/offers";
import {
  authorizeMarcheOfferPayment,
  marchePaymentStatusLabel,
} from "@/lib/marche/payments";

// Module-level guard so a single listing view counts once per session,
// even under StrictMode double-mount or quick back/forward navigation.
const VIEWED_IN_SESSION = new Set<string>();

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
  availability?: string | null;
  fulfillment_options?: string[] | null;
  photo_count?: number | null;
  store_id?: string | null;
  pricing_mode?: string | null;
  asking_price_gnf?: number | null;
  allow_offers?: boolean | null;
  quantity_in_stock?: number | null;
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
  const [metrics, setMetrics] = useState<{ views: number; saves: number; messages: number } | null>(null);
  const [store, setStore] = useState<MerchantStore | null>(null);
  const [interestCounts, setInterestCounts] = useState<{ total: number; pending: number }>({
    total: 0,
    pending: 0,
  });
  const [askedKinds, setAskedKinds] = useState<Set<InterestKind>>(new Set());
  const [offerOpen, setOfferOpen] = useState(false);
  const [myOffer, setMyOffer] = useState<MarketplaceOffer | null>(null);
  const { requireAuth } = useAuthGuard();

  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id ?? null;
      if (mounted) setSelfId(uid);

      const { data: l } = await supabase
        .from("marketplace_listings")
        .select("id, seller_id, kind, category, title, description, price_gnf, is_negotiable, is_urgent, delivery_available, condition, neighborhood, commune, landmark, created_at, availability, fulfillment_options, photo_count, store_id, pricing_mode, asking_price_gnf, allow_offers, quantity_in_stock")
        .eq("id", listingId)
        .maybeSingle();
      if (!mounted || !l) return;
      setListing(l as FullListing);

      const storeId = (l as unknown as { store_id?: string | null }).store_id ?? null;
      if (storeId) {
        const s = await getStoreById(storeId).catch(() => null);
        if (mounted) setStore(s);
      }

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
        const off = await getMyOfferForListing(listingId, uid);
        if (mounted) setMyOffer(off);
      }
    })();
    return () => {
      mounted = false;
    };
  }, [listingId]);

  // Fire a non-blocking view metric + load aggregate counters.
  useEffect(() => {
    if (!VIEWED_IN_SESSION.has(listingId)) {
      VIEWED_IN_SESSION.add(listingId);
      incrementListingMetric(listingId, "view");
    }
    let alive = true;
    (async () => {
      const m = await getListingMetrics(listingId);
      if (alive) setMetrics(m);
      const c = await countInterestsByListing([listingId]);
      if (alive) setInterestCounts(c.get(listingId) ?? { total: 0, pending: 0 });
    })();
    return () => {
      alive = false;
    };
  }, [listingId]);

  const toggleSave = async () => {
    if (!selfId) { requireAuth(); return; }
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
    if (!selfId) { requireAuth(); return; }
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
    incrementListingMetric(listing.id, "message");
    setOpenConv(created.id);
  };

  const sendInterest = async (kind: InterestKind, successMsg: string) => {
    if (!listing) return;
    if (!selfId) { requireAuth(); return; }
    if (selfId === listing.seller_id) {
      toast({ title: "Votre annonce", description: "Action réservée aux acheteurs." });
      return;
    }
    if (askedKinds.has(kind)) {
      toast({ title: "Déjà envoyé", description: "Le vendeur a été notifié." });
      return;
    }
    try {
      await createInterest({
        listingId: listing.id,
        buyerId: selfId,
        sellerId: listing.seller_id,
        kind,
      });
      setAskedKinds((s) => new Set(s).add(kind));
      setInterestCounts((c) => ({ total: c.total + 1, pending: c.pending + 1 }));
      toast({ title: successMsg, description: "Le vendeur sera notifié." });
    } catch (e) {
      toast({ title: "Erreur", description: (e as Error).message });
    }
  };

  if (!listing)
    return (
      <div className="max-w-md mx-auto p-6 text-center text-muted-foreground">Chargement…</div>
    );

  const location = [listing.neighborhood, listing.commune, listing.landmark].filter(Boolean).join(" · ") || "Conakry";
  const complete = isListingComplete(listing);
  const fulfillment = (listing.fulfillment_options ?? []) as FulfillmentId[];
  const sellerPhoneDigits = seller?.phone ? seller.phone.replace(/[^\d]/g, "") : "";
  const whatsappHref = sellerPhoneDigits
    ? `https://wa.me/${sellerPhoneDigits}?text=${encodeURIComponent(
        `Bonjour, je suis intéressé par votre annonce CHOPCHOP : ${listing.title}`,
      )}`
    : null;

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
          <img loading="lazy" decoding="async" src={images[imgIdx]} alt={listing.title} className="w-full h-full object-cover" />
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
            <AvailabilityChip value={listing.availability} />
            {listing.is_urgent && (
              <span className="px-2 py-0.5 rounded-full bg-destructive text-destructive-foreground text-xs font-semibold">
                Urgent
              </span>
            )}
            {listing.delivery_available && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-primary text-primary-foreground text-xs font-semibold">
                <Truck className="w-3 h-3" /> Livraison CHOPCHOP
              </span>
            )}
            <span className="px-2 py-0.5 rounded-full bg-muted text-foreground text-xs">
              {categoryLabel(listing.category)}
            </span>
            {listing.condition && (
              <span className="px-2 py-0.5 rounded-full bg-muted text-foreground text-xs">{listing.condition}</span>
            )}
            {complete && <CompleteListingChip />}
          </div>
          <p className="text-xs text-muted-foreground mt-2">Publié {timeAgo(listing.created_at)}</p>
        </div>

        <div className="flex items-center gap-2 text-sm text-foreground">
          <MapPin className="w-4 h-4 text-primary shrink-0" />
          <span>{location}</span>
        </div>

        {fulfillment.length > 0 && (
          <div>
            <p className="text-[11px] font-semibold text-muted-foreground mb-1.5">Options de remise</p>
            <FulfillmentChips options={fulfillment} />
          </div>
        )}

        {metrics && (metrics.views > 0 || metrics.saves > 0 || metrics.messages > 0) && (
          <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
            <span className="inline-flex items-center gap-1"><Eye className="w-3 h-3" />{metrics.views} vues</span>
            <span className="inline-flex items-center gap-1"><Heart className="w-3 h-3" />{metrics.saves} sauvegardes</span>
            <span className="inline-flex items-center gap-1"><MessageCircle className="w-3 h-3" />{metrics.messages} intéressés</span>
          </div>
        )}

        {interestCounts.total > 0 && (
          <div className="flex flex-wrap gap-2 text-[11px] text-muted-foreground">
            <span className="px-2 py-0.5 rounded-full bg-muted">
              {interestCounts.total} {interestCounts.total > 1 ? "personnes intéressées" : "personne intéressée"}
            </span>
            {interestCounts.pending > 0 && (
              <span className="px-2 py-0.5 rounded-full bg-muted">
                {interestCounts.pending} demande{interestCounts.pending > 1 ? "s" : ""} en attente
              </span>
            )}
          </div>
        )}

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
              <p className="font-semibold truncate">{seller?.full_name ?? "Vendeur CHOPCHOP"}</p>
              <div className="mt-0.5">
                <SellerBadge kind={listing.kind} />
              </div>
            </div>
          </div>
          <SellerTrustChips
            className="mt-3"
            kind={listing.kind}
            storeVerified={store?.verification_state === "verified"}
            chopDeliveryAvailable={
              fulfillment.includes("chop_delivery") || !!store?.delivery_available
            }
            choppayEnabled={!!store?.choppay_enabled}
            district={store?.district ?? listing.commune ?? listing.neighborhood ?? null}
          />
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
        {whatsappHref && (
          <a href={whatsappHref} target="_blank" rel="noopener noreferrer" className="block">
            <Button variant="outline" className="w-full">
              Continuer sur WhatsApp
            </Button>
          </a>
        )}

        {/* Phase 3 — calm interest pipeline */}
        {selfId !== listing.seller_id && (
          <div className="grid grid-cols-2 gap-2">
            <Button
              variant="outline"
              className="w-full"
              onClick={() => sendInterest("availability", "Disponibilité demandée")}
              disabled={askedKinds.has("availability")}
            >
              <PackageSearch className="w-4 h-4 mr-1" />
              {askedKinds.has("availability") ? "Demandé" : "Disponibilité"}
            </Button>
            <Button
              variant="outline"
              className="w-full"
              onClick={() => sendInterest("delivery", "Livraison demandée")}
              disabled={askedKinds.has("delivery")}
            >
              <Truck className="w-4 h-4 mr-1" />
              {askedKinds.has("delivery") ? "Demandé" : "Livraison"}
            </Button>
            <Button
              variant="ghost"
              className="w-full col-span-2 text-muted-foreground"
              onClick={() => sendInterest("reservation", "Réservation demandée")}
              disabled={askedKinds.has("reservation") || listing.availability === "reserved" || listing.availability === "sold"}
            >
              <CalendarCheck className="w-4 h-4 mr-1" />
              {listing.availability === "reserved"
                ? "Déjà réservé"
                : askedKinds.has("reservation")
                  ? "Réservation envoyée"
                  : "Demander à réserver"}
            </Button>
          </div>
        )}

        {/* Bargaining — only if merchant enabled it */}
        {selfId !== listing.seller_id && listing.allow_offers && listing.pricing_mode === "negotiable" && (
          <div className="rounded-2xl border border-primary/40 bg-primary/5 p-3 space-y-2">
            <div className="flex items-center gap-2 text-sm font-semibold">
              <Tag className="w-4 h-4 text-primary" /> Négociable
            </div>
            {myOffer ? (
              <div className="space-y-1.5">
                <p className="text-xs text-muted-foreground">
                  Votre offre : <b>{formatGNF(myOffer.offer_amount_gnf)}</b> · {offerStatusLabel(myOffer.status)}
                </p>
                {myOffer.status === "countered" && myOffer.counter_amount_gnf && (
                  <p className="text-xs text-foreground">
                    Contre-proposition du marchand : <b>{formatGNF(myOffer.counter_amount_gnf)}</b>
                  </p>
                )}
                {myOffer.merchant_message && (
                  <p className="text-xs text-muted-foreground italic">« {myOffer.merchant_message} »</p>
                )}
                {(myOffer.status === "pending" || myOffer.status === "countered") && (
                  <Button
                    variant="outline" size="sm" className="w-full"
                    onClick={async () => {
                      try {
                        await withdrawOffer(myOffer.id);
                        const refreshed = selfId ? await getMyOfferForListing(listing.id, selfId) : null;
                        setMyOffer(refreshed);
                        toast({ title: "Offre retirée" });
                      } catch (e: any) {
                        toast({ title: "Erreur", description: e?.message });
                      }
                    }}
                  >
                    Retirer mon offre
                  </Button>
                )}
                {(myOffer.status === "rejected" || myOffer.status === "withdrawn" || myOffer.status === "expired") && (
                  <Button size="sm" className="w-full" onClick={() => requireAuth(() => setOfferOpen(true))}>
                    Faire une nouvelle offre
                  </Button>
                )}
                {myOffer.status === "accepted" && (
                  <AcceptedOfferPaymentBlock
                    offer={myOffer}
                    onPaid={async () => {
                      if (selfId) {
                        const refreshed = await getMyOfferForListing(listing.id, selfId);
                        setMyOffer(refreshed);
                      }
                    }}
                  />
                )}
              </div>
            ) : (
              <Button size="sm" className="w-full" onClick={() => requireAuth(() => setOfferOpen(true))}>
                <Tag className="w-4 h-4 mr-1" /> Faire une offre
              </Button>
            )}
          </div>
        )}
      </div>

      <ReportModal listingId={listing.id} open={reportOpen} onOpenChange={setReportOpen} />
      <OfferSheet
        open={offerOpen}
        onOpenChange={setOfferOpen}
        listingId={listing.id}
        askingPrice={listing.asking_price_gnf ?? listing.price_gnf}
        onCreated={async () => {
          if (selfId) {
            const o = await getMyOfferForListing(listing.id, selfId);
            setMyOffer(o);
          }
        }}
      />
      {openConv && selfId && (
        <ChatThread
          conversationId={openConv}
          selfId={selfId}
          peerName={seller?.full_name ?? "Vendeur"}
          peerPhone={seller?.phone ?? null}
          listingTitle={listing.title}
          listingPrice={listing.price_gnf}
          listingAvailability={listing.availability ? availabilityLabel(listing.availability) : null}
          listingId={listing.id}
          sellerId={listing.seller_id}
          listingCategory={listing.category}
          listingNeighborhood={listing.neighborhood}
          listingCommune={listing.commune}
          listingLandmark={listing.landmark}
          storeId={listing.store_id ?? null}
          storeName={store?.name ?? null}
          deliveryEligible={
            listing.delivery_available ||
            fulfillment.includes("chop_delivery") ||
            !!store?.delivery_available
          }
          onBack={() => setOpenConv(null)}
        />
      )}
    </div>
  );
}

function AcceptedOfferPaymentBlock({
  offer,
  onPaid,
}: {
  offer: MarketplaceOffer;
  onPaid: () => Promise<void> | void;
}) {
  const [busy, setBusy] = useState(false);
  const amount = offer.counter_amount_gnf ?? offer.offer_amount_gnf;
  const status = (offer.payment_status ?? "unpaid") as string;

  const canPay = status === "unpaid" || status === "failed" || status === "cancelled";

  const pay = async () => {
    setBusy(true);
    try {
      const r = await authorizeMarcheOfferPayment(offer.id);
      if (r.paymentStatus === "authorized") {
        toast({ title: "Paiement autorisé", description: "Le vendeur peut préparer l'article." });
      } else if (r.paymentStatus === "failed") {
        toast({
          title: "Solde CHOP insuffisant",
          description: "Rechargez votre wallet ou choisissez un autre mode.",
          variant: "destructive" as any,
        });
      } else {
        toast({ title: "Paiement en cours", description: marchePaymentStatusLabel(r.paymentStatus) });
      }
      await onPaid();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-2 rounded-xl bg-background/60 p-2 border border-primary/20">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-medium">Paiement Marché</span>
        <span className="text-[11px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
          {marchePaymentStatusLabel(status)}
        </span>
      </div>
      <p className="text-xs text-muted-foreground">
        Montant convenu : <b className="text-foreground">{formatGNF(amount)}</b>
      </p>
      {canPay && (
        <Button size="sm" className="w-full" disabled={busy} onClick={pay}>
          {busy ? "Autorisation…" : "Payer avec CHOP Wallet"}
        </Button>
      )}
      {status === "authorized" && (
        <p className="text-[11px] text-success">
          Paiement autorisé. Le règlement au vendeur se fera après remise/livraison.
        </p>
      )}
      {status === "paid" && (
        <p className="text-[11px] text-success">Paiement réglé.</p>
      )}
    </div>
  );
}