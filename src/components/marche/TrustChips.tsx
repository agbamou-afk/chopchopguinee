import { BadgeCheck, ShieldCheck, Truck, CreditCard, Sparkles, MapPin, Camera, Store, Users } from "lucide-react";
import {
  availabilityLabel,
  fulfillmentLabel,
  type FulfillmentId,
  type SellerKind,
} from "@/lib/marche";

const baseChip =
  "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold border";

/** Seller trust (lightweight, never faked). */
export function SellerTrustChips({
  kind,
  isNew,
  identityVerified,
  storeVerified,
  chopDeliveryAvailable,
  choppayEnabled,
  district,
  className,
}: {
  kind: SellerKind;
  isNew?: boolean;
  identityVerified?: boolean;
  storeVerified?: boolean;
  chopDeliveryAvailable?: boolean;
  choppayEnabled?: boolean;
  district?: string | null;
  className?: string;
}) {
  return (
    <div className={`flex flex-wrap gap-1.5 ${className ?? ""}`}>
      {isNew && (
        <span className={`${baseChip} bg-muted border-border text-muted-foreground`}>
          <Sparkles className="w-3 h-3" /> Nouveau vendeur
        </span>
      )}
      {kind === "merchant" && (
        <span className={`${baseChip} bg-muted border-border text-foreground/80`}>
          <Store className="w-3 h-3" /> Boutique
        </span>
      )}
      {kind === "community" && !isNew && (
        <span className={`${baseChip} bg-muted border-border text-foreground/70`}>
          <Users className="w-3 h-3" /> Vendeur communauté
        </span>
      )}
      {identityVerified && (
        <span className={`${baseChip} bg-muted border-border text-foreground/80`}>
          <ShieldCheck className="w-3 h-3" /> Identité vérifiée
        </span>
      )}
      {storeVerified && (
        <span className={`${baseChip} bg-muted border-border text-foreground/80`}>
          <BadgeCheck className="w-3 h-3 text-primary" /> Boutique vérifiée
        </span>
      )}
      {chopDeliveryAvailable && (
        <span className={`${baseChip} bg-muted border-border text-foreground/80`}>
          <Truck className="w-3 h-3" /> Livraison CHOP
        </span>
      )}
      {choppayEnabled && (
        <span className={`${baseChip} bg-muted border-border text-foreground/80`}>
          <CreditCard className="w-3 h-3" /> WONGO Pay
        </span>
      )}
      {district && (
        <span className={`${baseChip} bg-muted border-border text-muted-foreground`}>
          <MapPin className="w-3 h-3" /> {district}
        </span>
      )}
    </div>
  );
}

/** Availability — calm pill with subtle tonal differentiation. */
export function AvailabilityChip({ value, compact }: { value?: string | null; compact?: boolean }) {
  const id = value ?? "to_confirm";
  const tone =
    id === "available"
      ? "bg-success/10 text-success border-success/20"
      : id === "limited"
        ? "bg-warning/10 text-warning border-warning/20"
        : id === "reserved"
          ? "bg-muted text-muted-foreground border-border"
          : id === "sold"
            ? "bg-muted text-muted-foreground border-border"
            : "bg-muted text-foreground/70 border-border";
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border font-semibold ${tone} ${
        compact ? "px-1.5 py-0.5 text-[10px]" : "px-2 py-0.5 text-[11px]"
      }`}
    >
      {availabilityLabel(id)}
    </span>
  );
}

/** Fulfillment chips — describes how the deal can complete. */
export function FulfillmentChips({
  options,
  max,
}: {
  options: FulfillmentId[] | string[] | null | undefined;
  max?: number;
}) {
  const list = (options ?? []).filter(Boolean) as string[];
  if (list.length === 0) return null;
  const shown = typeof max === "number" ? list.slice(0, max) : list;
  return (
    <div className="flex flex-wrap gap-1">
      {shown.map((id) => (
        <span
          key={id}
          className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-muted text-foreground/80 text-[10px] font-medium border border-border"
        >
          {id === "chop_delivery" || id === "seller_delivery" ? <Truck className="w-2.5 h-2.5" /> : null}
          {fulfillmentLabel(id)}
        </span>
      ))}
    </div>
  );
}

/** "Annonce complète" — only when listing is genuinely complete. */
export function CompleteListingChip() {
  return (
    <span className={`${baseChip} bg-success/10 border-success/20 text-success`}>
      <Camera className="w-3 h-3" /> Annonce complète
    </span>
  );
}