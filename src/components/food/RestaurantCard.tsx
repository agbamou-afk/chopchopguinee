import { motion } from "framer-motion";
import { Star, Clock, MapPin } from "lucide-react";

interface RestaurantCardProps {
  name: string;
  image: string;
  rating: number;
  deliveryTime: string;
  distance: string;
  category: string;
  onClick?: () => void;
}

export function RestaurantCard({
  name,
  image,
  rating,
  deliveryTime,
  distance,
  category,
  onClick,
}: RestaurantCardProps) {
  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="w-full bg-card rounded-2xl overflow-hidden shadow-card hover:shadow-elevated transition-shadow text-left"
    >
      <div className="relative h-32">
        <img
          src={image}
          alt={name}
          loading="lazy"
          decoding="async"
          className="w-full h-full object-cover"
        />
        <div className="absolute top-2 right-2 bg-card/90 backdrop-blur-sm px-2 py-1 rounded-full flex items-center gap-1">
          <Star className="w-3 h-3 text-secondary fill-secondary" />
          <span className="text-xs font-medium text-foreground">{rating}</span>
        </div>
      </div>
      <div className="p-3">
        <h3 className="font-semibold text-foreground mb-1">{name}</h3>
        <p className="text-xs text-muted-foreground mb-2">{category}</p>
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          <div className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            <span>{deliveryTime}</span>
          </div>
          <div className="flex items-center gap-1">
            <MapPin className="w-3 h-3" />
            <span>{distance}</span>
          </div>
        </div>
      </div>
    </motion.button>
  );
}
