import { motion } from "framer-motion";
import { ArrowLeft, Search, Filter } from "lucide-react";
import { useState } from "react";
import { ProductCard } from "@/components/market/ProductCard";
import { toast } from "sonner";

interface MarketViewProps {
  onBack: () => void;
}

const categories = [
  { id: "all", name: "Tout" },
  { id: "electronics", name: "Électronique" },
  { id: "fashion", name: "Mode" },
  { id: "home", name: "Maison" },
  { id: "beauty", name: "Beauté" },
];

const products = [
  {
    name: "Smartphone Samsung Galaxy A54",
    image: "https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=400&h=300&fit=crop",
    price: 3500000,
    originalPrice: 4200000,
    rating: 4.7,
    soldCount: 234,
  },
  {
    name: "Écouteurs sans fil Bluetooth",
    image: "https://images.unsplash.com/photo-1590658268037-6bf12165a8df?w=400&h=300&fit=crop",
    price: 150000,
    originalPrice: 200000,
    rating: 4.5,
    soldCount: 567,
  },
  {
    name: "Robe traditionnelle Bazin",
    image: "https://images.unsplash.com/photo-1594938298603-c8148c4dae35?w=400&h=300&fit=crop",
    price: 350000,
    rating: 4.9,
    soldCount: 89,
  },
  {
    name: "Montre connectée Sport",
    image: "https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400&h=300&fit=crop",
    price: 250000,
    originalPrice: 350000,
    rating: 4.3,
    soldCount: 156,
  },
  {
    name: "Sac à main en cuir",
    image: "https://images.unsplash.com/photo-1548036328-c9fa89d128fa?w=400&h=300&fit=crop",
    price: 180000,
    rating: 4.6,
    soldCount: 78,
  },
  {
    name: "Parfum Oriental Luxe",
    image: "https://images.unsplash.com/photo-1541643600914-78b084683601?w=400&h=300&fit=crop",
    price: 120000,
    originalPrice: 180000,
    rating: 4.8,
    soldCount: 312,
  },
];

export function MarketView({ onBack }: MarketViewProps) {
  const [activeCategory, setActiveCategory] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");

  const handleAddToCart = (productName: string) => {
    toast.success(`${productName} ajouté au panier`);
  };

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
          <h1 className="text-xl font-bold text-foreground">Marché Choper</h1>
        </div>

        {/* Search */}
        <div className="flex items-center gap-2 mb-4">
          <div className="flex-1 flex items-center gap-3 bg-muted rounded-xl px-4 py-3">
            <Search className="w-5 h-5 text-muted-foreground" />
            <input
              type="text"
              placeholder="Rechercher un produit..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="flex-1 bg-transparent placeholder:text-muted-foreground focus:outline-none text-sm text-foreground"
            />
          </div>
          <button className="p-3 bg-primary rounded-xl">
            <Filter className="w-5 h-5 text-primary-foreground" />
          </button>
        </div>

        {/* Categories */}
        <div className="flex gap-2 overflow-x-auto scrollbar-hide -mx-4 px-4 pb-2">
          {categories.map((cat) => (
            <button
              key={cat.id}
              onClick={() => setActiveCategory(cat.id)}
              className={`px-4 py-2 rounded-full whitespace-nowrap transition-colors text-sm font-medium ${
                activeCategory === cat.id
                  ? "gradient-primary text-primary-foreground"
                  : "bg-muted text-foreground hover:bg-muted/80"
              }`}
            >
              {cat.name}
            </button>
          ))}
        </div>
      </motion.header>

      {/* Products */}
      <div className="px-4 pt-2 pb-6">
        <div className="grid grid-cols-2 gap-3">
          {products
            .filter((p) =>
              p.name.toLowerCase().includes(searchQuery.toLowerCase())
            )
            .map((product, index) => (
              <motion.div
                key={product.name}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
              >
                <ProductCard
                  {...product}
                  onAddToCart={() => handleAddToCart(product.name)}
                />
              </motion.div>
            ))}
        </div>
      </div>
    </div>
  );
}
