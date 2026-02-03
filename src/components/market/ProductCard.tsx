import { motion } from "framer-motion";
import { Star, ShoppingCart } from "lucide-react";

interface ProductCardProps {
  name: string;
  image: string;
  price: number;
  originalPrice?: number;
  rating: number;
  soldCount: number;
  onAddToCart?: () => void;
}

export function ProductCard({
  name,
  image,
  price,
  originalPrice,
  rating,
  soldCount,
  onAddToCart,
}: ProductCardProps) {
  const formatMoney = (amount: number) =>
    new Intl.NumberFormat("fr-GN").format(amount);

  const discount = originalPrice
    ? Math.round(((originalPrice - price) / originalPrice) * 100)
    : 0;

  return (
    <motion.div
      whileHover={{ y: -4 }}
      className="bg-card rounded-2xl overflow-hidden shadow-card"
    >
      <div className="relative">
        <img
          src={image}
          alt={name}
          className="w-full h-32 object-cover"
        />
        {discount > 0 && (
          <span className="absolute top-2 left-2 bg-destructive text-destructive-foreground text-xs font-bold px-2 py-1 rounded-full">
            -{discount}%
          </span>
        )}
      </div>
      <div className="p-3">
        <h3 className="text-sm font-medium text-foreground line-clamp-2 mb-2">
          {name}
        </h3>
        <div className="flex items-center gap-1 mb-2">
          <Star className="w-3 h-3 text-secondary fill-secondary" />
          <span className="text-xs text-muted-foreground">
            {rating} • {soldCount} vendus
          </span>
        </div>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-bold text-primary">
              {formatMoney(price)} GNF
            </p>
            {originalPrice && (
              <p className="text-xs text-muted-foreground line-through">
                {formatMoney(originalPrice)} GNF
              </p>
            )}
          </div>
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            onClick={onAddToCart}
            className="p-2 rounded-xl gradient-primary shadow-soft"
          >
            <ShoppingCart className="w-4 h-4 text-primary-foreground" />
          </motion.button>
        </div>
      </div>
    </motion.div>
  );
}
