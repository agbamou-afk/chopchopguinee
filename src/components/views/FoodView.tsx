import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Search, SlidersHorizontal } from "lucide-react";
import { useMemo, useState } from "react";
import { FoodCategories } from "@/components/food/FoodCategories";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import { RestaurantDetail, type Restaurant } from "@/components/food/RestaurantDetail";

interface FoodViewProps {
  onBack: () => void;
}

const allRestaurants: Restaurant[] = [
  {
    name: "Chez Mama Fatoumata",
    image: "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400&h=300&fit=crop",
    rating: 4.8,
    deliveryTime: "20-30 min",
    distance: "1.2 km",
    category: "Cuisine locale",
    menu: [
      { id: "m1", name: "Riz au gras", description: "Riz parfumé, viande mijotée, sauce tomate", price: 35000 },
      { id: "m2", name: "Poulet braisé", description: "Demi-poulet braisé, attiéké et piment", price: 55000 },
      { id: "m3", name: "Foutou banane", description: "Foutou banane, sauce graine traditionnelle", price: 40000 },
    ],
  },
  {
    name: "Grillades du Port",
    image: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&h=300&fit=crop",
    rating: 4.6,
    deliveryTime: "25-35 min",
    distance: "2.1 km",
    category: "Grillades",
    menu: [
      { id: "g1", name: "Brochettes de bœuf", description: "5 brochettes marinées, frites, salade", price: 45000 },
      { id: "g2", name: "Capitaine grillé", description: "Capitaine entier, riz blanc, sauce piment", price: 70000 },
    ],
  },
  {
    name: "Le Palmier",
    image: "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400&h=300&fit=crop",
    rating: 4.5,
    deliveryTime: "30-40 min",
    distance: "3.0 km",
    category: "Cuisine locale",
    menu: [
      { id: "p1", name: "Plat du jour", description: "Selon la cuisinière du jour", price: 38000 },
    ],
  },
  {
    name: "Café Conakry",
    image: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400&h=300&fit=crop",
    rating: 4.7,
    deliveryTime: "15-25 min",
    distance: "0.8 km",
    category: "Boissons",
    menu: [
      { id: "c1", name: "Café noir", description: "Espresso de Guinée forestière", price: 8000 },
      { id: "c2", name: "Jus de bissap", description: "Frais, hibiscus & gingembre", price: 12000 },
    ],
  },
  {
    name: "La Terrasse",
    image: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&h=300&fit=crop",
    rating: 4.4,
    deliveryTime: "35-45 min",
    distance: "4.2 km",
    category: "Grillades",
    menu: [
      { id: "t1", name: "Mouton braisé", description: "Avec attiéké et oignons", price: 60000 },
    ],
  },
  {
    name: "Pâtisserie Belle Vue",
    image: "https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400&h=300&fit=crop",
    rating: 4.9,
    deliveryTime: "20-30 min",
    distance: "1.5 km",
    category: "Desserts",
    menu: [
      { id: "b1", name: "Tarte mangue", description: "Pâte sablée, mangue de Kindia", price: 25000 },
      { id: "b2", name: "Cookies coco", description: "Lot de 4 cookies maison", price: 15000 },
    ],
  },
];

type SortKey = "rating" | "time" | "distance";

export function FoodView({ onBack }: FoodViewProps) {
  const [activeCategory, setActiveCategory] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [sort, setSort] = useState<SortKey>("rating");
  const [active, setActive] = useState<Restaurant | null>(null);

  const visible = useMemo(() => {
    const filtered = allRestaurants.filter((r) =>
      r.name.toLowerCase().includes(searchQuery.toLowerCase()),
    );
    const parseFirst = (s: string) => parseFloat(s.replace(",", ".")) || 0;
    return [...filtered].sort((a, b) => {
      if (sort === "rating") return b.rating - a.rating;
      if (sort === "time") return parseFirst(a.deliveryTime) - parseFirst(b.deliveryTime);
      return parseFirst(a.distance) - parseFirst(b.distance);
    });
  }, [searchQuery, sort]);

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

        {/* Sort */}
        <div className="flex items-center gap-2 mt-3 overflow-x-auto scrollbar-none -mx-4 px-4">
          <span className="flex items-center gap-1 text-xs text-muted-foreground shrink-0">
            <SlidersHorizontal className="w-3.5 h-3.5" /> Trier :
          </span>
          {([
            ["rating", "Mieux notés"],
            ["time", "Plus rapides"],
            ["distance", "Plus proches"],
          ] as const).map(([k, label]) => (
            <button
              key={k}
              onClick={() => setSort(k)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-xs font-medium transition ${
                sort === k
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-muted-foreground"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </motion.header>

      {/* Restaurant list */}
      <div className="px-4 pt-2 pb-6">
        <div className="grid grid-cols-2 gap-3">
          {visible.map((restaurant, index) => (
              <motion.div
                key={restaurant.name}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
              >
                <RestaurantCard {...restaurant} onClick={() => setActive(restaurant)} />
              </motion.div>
            ))}
        </div>
      </div>

      <AnimatePresence>
        {active && (
          <RestaurantDetail restaurant={active} onClose={() => setActive(null)} />
        )}
      </AnimatePresence>
    </div>
  );
}
