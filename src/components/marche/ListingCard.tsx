import { motion } from "framer-motion";
import { MapPin, Truck, Flame } from "lucide-react";
import { formatGNF, timeAgo, type SellerKind } from "@/lib/marche";
import { SellerBadge } from "./SellerBadge";

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
}

export function ListingCard({ l, onClick }: { l: ListingCardData; onClick: () => void }) {
  const location = [l.neighborhood, l.commune].filter(Boolean).join(", ") || "Conakry";
  return (
    <motion.button
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="text-left bg-card rounded-2xl overflow-hidden shadow-card hover:shadow-elevated transition-shadow"
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
      </div>
    </motion.button>
  );
}