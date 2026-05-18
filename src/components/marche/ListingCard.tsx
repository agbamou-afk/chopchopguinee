import { motion } from "framer-motion";
import { MapPin, Truck, Flame, Eye, Heart } from "lucide-react";
import { formatGNF, timeAgo, isListingComplete, type SellerKind, type FulfillmentId } from "@/lib/marche";
import { SellerBadge } from "./SellerBadge";
import { AvailabilityChip, CompleteListingChip } from "./TrustChips";

export interface ListingCardData {
  id: string;
  title: string;
  price_gnf: number | null;
  is_negotiable: boolean;
  is_urgent: boolean;
  delivery_available: boolean;
  neighborhood: string | null;
  commune: string | null;
  created_at: string;
  kind: SellerKind;
  cover_url?: string | null;
  views?: number;
  saves?: number;
  availability?: string | null;
  fulfillment_options?: FulfillmentId[] | string[] | null;
  photo_count?: number | null;
  condition?: string | null;
  description?: string | null;
}

export function ListingCard({ l, onClick }: { l: ListingCardData; onClick: () => void }) {
  const location = [l.neighborhood, l.commune].filter(Boolean).join(", ") || "Conakry";
  const showMetrics = (l.views ?? 0) > 0 || (l.saves ?? 0) > 0;
  const softened = l.availability === "sold" || l.availability === "reserved";
  const complete = isListingComplete({
    photo_count: l.photo_count,
    description: l.description,
    condition: l.condition,
    neighborhood: l.neighborhood,
    commune: l.commune,
    price_gnf: l.price_gnf,
  });
  return (
    <motion.button
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className={`text-left bg-card rounded-2xl overflow-hidden shadow-card hover:shadow-elevated transition-shadow ${
        softened ? "opacity-70" : ""
      }`}
    >
      <div className="relative aspect-square bg-muted">
        {l.cover_url ? (
          <img src={l.cover_url} alt={l.title} loading="lazy" className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-muted-foreground text-xs">
            Aucune photo
          </div>
        )}
        {l.is_urgent && (
          <span className="absolute top-2 left-2 inline-flex items-center gap-1 bg-destructive text-destructive-foreground text-[10px] font-bold px-2 py-0.5 rounded-full">
            <Flame className="w-3 h-3" /> Urgent
          </span>
        )}
        <div className="absolute top-2 right-2">
          <AvailabilityChip value={l.availability} compact />
        </div>
        {l.delivery_available && (
          <span className="absolute bottom-2 left-2 inline-flex items-center gap-1 bg-primary text-primary-foreground text-[10px] font-semibold px-2 py-0.5 rounded-full">
            <Truck className="w-3 h-3" /> Livraison
          </span>
        )}
      </div>
      <div className="p-2.5">
        <p className="text-sm font-semibold text-foreground line-clamp-2 leading-tight min-h-[2.5em]">
          {l.title}
        </p>
        <p className="text-sm font-bold text-primary mt-1">
          {formatGNF(l.price_gnf)}
          {l.is_negotiable && <span className="text-[10px] font-medium text-muted-foreground ml-1">Négociable</span>}
        </p>
        <div className="flex items-center gap-1 mt-1 text-[10px] text-muted-foreground">
          <MapPin className="w-3 h-3 shrink-0" />
          <span className="truncate">{location}</span>
        </div>
        <div className="flex items-center justify-between mt-1.5">
          <SellerBadge kind={l.kind} />
          <span className="text-[10px] text-muted-foreground">{timeAgo(l.created_at)}</span>
        </div>
        {complete && (
          <div className="mt-1.5">
            <CompleteListingChip />
          </div>
        )}
        {showMetrics && (
          <div className="flex items-center gap-2 mt-1 text-[10px] text-muted-foreground">
            {(l.views ?? 0) > 0 && (
              <span className="inline-flex items-center gap-0.5"><Eye className="w-3 h-3" />{l.views}</span>
            )}
            {(l.saves ?? 0) > 0 && (
              <span className="inline-flex items-center gap-0.5"><Heart className="w-3 h-3" />{l.saves}</span>
            )}
          </div>
        )}
      </div>
    </motion.button>
  );
}