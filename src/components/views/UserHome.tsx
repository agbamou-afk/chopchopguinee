import { motion } from "framer-motion";
import { Bell, Search, ToggleRight } from "lucide-react";
import { WalletCard } from "@/components/home/WalletCard";
import { QuickActions } from "@/components/home/QuickActions";
import { PromoCarousel } from "@/components/home/PromoCarousel";
import { RestaurantCard } from "@/components/food/RestaurantCard";

interface UserHomeProps {
  onActionClick: (action: string) => void;
  onToggleDriverMode: () => void;
}

const popularRestaurants = [
  {
    name: "Chez Mama Fatoumata",
    image: "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400&h=300&fit=crop",
    rating: 4.8,
    deliveryTime: "20-30 min",
    distance: "1.2 km",
    category: "Cuisine locale",
  },
  {
    name: "Grillades du Port",
    image: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&h=300&fit=crop",
    rating: 4.6,
    deliveryTime: "25-35 min",
    distance: "2.1 km",
    category: "Grillades",
  },
];

export function UserHome({ onActionClick, onToggleDriverMode }: UserHomeProps) {
  return (
    <div className="max-w-md mx-auto">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="gradient-hero text-primary-foreground px-4 pt-6 pb-8 rounded-b-3xl"
      >
        <div className="flex items-center justify-between mb-6">
          <div>
            <p className="text-sm opacity-80">Bonjour 👋</p>
            <h1 className="text-xl font-bold">Bienvenue sur Chop Chop</h1>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={onToggleDriverMode}
              className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition-colors"
              title="Mode chauffeur"
            >
              <ToggleRight className="w-5 h-5" />
            </button>
            <button className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition-colors relative">
              <Bell className="w-5 h-5" />
              <span className="absolute top-1 right-1 w-2 h-2 bg-secondary rounded-full" />
            </button>
          </div>
        </div>

        {/* Search bar */}
        <div className="flex items-center gap-3 bg-white/20 backdrop-blur-sm rounded-xl px-4 py-3">
          <Search className="w-5 h-5 opacity-70" />
          <input
            type="text"
            placeholder="Où voulez-vous aller ?"
            className="flex-1 bg-transparent placeholder:text-white/70 focus:outline-none text-sm"
          />
        </div>
      </motion.header>

      {/* Content */}
      <div className="px-4 -mt-4 space-y-6">
        {/* Wallet */}
        <WalletCard
          balance={2500000}
          onSend={() => onActionClick("send")}
          onReceive={() => onActionClick("scan")}
        />

        {/* Quick Actions */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-4">Services</h2>
          <QuickActions onActionClick={onActionClick} />
        </section>

        {/* Promos */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-4">Offres spéciales</h2>
          <PromoCarousel />
        </section>

        {/* Popular restaurants */}
        <section className="pb-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-foreground">Restaurants populaires</h2>
            <button 
              onClick={() => onActionClick("food")}
              className="text-sm font-medium text-primary"
            >
              Voir tout
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3">
            {popularRestaurants.map((restaurant) => (
              <RestaurantCard
                key={restaurant.name}
                {...restaurant}
                onClick={() => onActionClick("food")}
              />
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
