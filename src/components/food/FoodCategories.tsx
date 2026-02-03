import { motion } from "framer-motion";

const categories = [
  { id: "all", name: "Tout", emoji: "🍽️" },
  { id: "local", name: "Local", emoji: "🍚" },
  { id: "grilled", name: "Grillades", emoji: "🍖" },
  { id: "drinks", name: "Boissons", emoji: "🧃" },
  { id: "dessert", name: "Desserts", emoji: "🍰" },
];

interface FoodCategoriesProps {
  activeCategory: string;
  onCategoryChange: (category: string) => void;
}

export function FoodCategories({ activeCategory, onCategoryChange }: FoodCategoriesProps) {
  return (
    <div className="flex gap-2 overflow-x-auto scrollbar-hide -mx-4 px-4 pb-2">
      {categories.map((cat) => (
        <motion.button
          key={cat.id}
          whileTap={{ scale: 0.95 }}
          onClick={() => onCategoryChange(cat.id)}
          className={`flex items-center gap-2 px-4 py-2 rounded-full whitespace-nowrap transition-colors ${
            activeCategory === cat.id
              ? "gradient-primary text-primary-foreground"
              : "bg-muted text-foreground hover:bg-muted/80"
          }`}
        >
          <span>{cat.emoji}</span>
          <span className="text-sm font-medium">{cat.name}</span>
        </motion.button>
      ))}
    </div>
  );
}
