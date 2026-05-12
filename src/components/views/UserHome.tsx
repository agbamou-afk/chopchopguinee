import { QuickActions } from "@/components/home/QuickActions";
import { PromoCarousel } from "@/components/home/PromoCarousel";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import { AppHeader } from "@/components/ui/AppHeader";

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
  const walletBalance = 2500000;
  return (
    <div className="max-w-md mx-auto">
      <AppHeader
        isDriverMode={false}
        onToggleDriverMode={onToggleDriverMode}
        amountLabel="Solde portefeuille"
        amountValue={walletBalance}
        notificationCount={1}
        onAmountClick={() => onActionClick("send")}
      />

      {/* Content */}
      <div className="px-4 mt-6 space-y-6">
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
