import { motion } from "framer-motion";
import { ArrowLeft, Search } from "lucide-react";
import { useState } from "react";
import { FoodCategories } from "@/components/food/FoodCategories";
import { RestaurantCard } from "@/components/food/RestaurantCard";

interface FoodViewProps {
  onBack: () => void;
}

const allRestaurants = [
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
  {
    name: "Le Palmier",
    image: "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400&h=300&fit=crop",
    rating: 4.5,
    deliveryTime: "30-40 min",
    distance: "3.0 km",
    category: "Cuisine locale",
  },
  {
    name: "Café Conakry",
    image: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400&h=300&fit=crop",
    rating: 4.7,
    deliveryTime: "15-25 min",
    distance: "0.8 km",
    category: "Boissons",
  },
  {
    name: "La Terrasse",
    image: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&h=300&fit=crop",
    rating: 4.4,
    deliveryTime: "35-45 min",
    distance: "4.2 km",
    category: "Grillades",
  },
  {
    name: "Pâtisserie Belle Vue",
    image: "https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400&h=300&fit=crop",
    rating: 4.9,
    deliveryTime: "20-30 min",
    distance: "1.5 km",
    category: "Desserts",
  },
];

export function FoodView({ onBack }: FoodViewProps) {
  const [activeCategory, setActiveCategory] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");

  return (
    <div className="max-w-md mx-auto">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="bg-card px-4 pt-6 pb-4 sticky top-0 z-40"
      >
        <div className="flex items-center gap-4 mb-4">
          <button
            onClick={onBack}
            className="p-2 rounded-full bg-muted hover:bg-muted/80 transition-colors"
          >
            <ArrowLeft className="w-5 h-5 text-foreground" />
          </button>
          <h1 className="text-xl font-bold text-foreground">Commander un repas</h1>
        </div>

        {/* Search */}
        <div className="flex items-center gap-3 bg-muted rounded-xl px-4 py-3 mb-4">
          <Search className="w-5 h-5 text-muted-foreground" />
          <input
            type="text"
            placeholder="Rechercher un restaurant..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="flex-1 bg-transparent placeholder:text-muted-foreground focus:outline-none text-sm text-foreground"
          />
        </div>

        {/* Categories */}
        <FoodCategories
          activeCategory={activeCategory}
          onCategoryChange={setActiveCategory}
        />
      </motion.header>

      {/* Restaurant list */}
      <div className="px-4 pt-2 pb-6">
        <div className="grid grid-cols-2 gap-3">
          {allRestaurants
            .filter((r) =>
              r.name.toLowerCase().includes(searchQuery.toLowerCase())
            )
            .map((restaurant, index) => (
              <motion.div
                key={restaurant.name}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
              >
                <RestaurantCard {...restaurant} />
              </motion.div>
            ))}
        </div>
      </div>
    </div>
  );
}
