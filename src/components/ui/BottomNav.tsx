import { Home, ShoppingBag, Wallet, User, Car } from "lucide-react";
import { motion } from "framer-motion";

interface BottomNavProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  isDriverMode?: boolean;
}

const userTabs = [
  { id: "home", icon: Home, label: "Accueil" },
  { id: "orders", icon: ShoppingBag, label: "Commandes" },
  { id: "wallet", icon: Wallet, label: "Portefeuille" },
  { id: "profile", icon: User, label: "Profil" },
];

const driverTabs = [
  { id: "home", icon: Home, label: "Tableau" },
  { id: "orders", icon: Car, label: "Courses" },
  { id: "wallet", icon: Wallet, label: "Gains" },
  { id: "profile", icon: User, label: "Profil" },
];

export function BottomNav({ activeTab, onTabChange, isDriverMode = false }: BottomNavProps) {
  const tabs = isDriverMode ? driverTabs : userTabs;

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-card border-t border-border px-4 py-2 z-50">
      <div className="max-w-md mx-auto flex justify-around items-center">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className="relative flex flex-col items-center py-2 px-4"
          >
            {activeTab === tab.id && (
              <motion.div
                layoutId="activeTab"
                className="absolute inset-0 bg-primary/10 rounded-xl"
                transition={{ type: "spring", bounce: 0.2, duration: 0.6 }}
              />
            )}
            <tab.icon
              className={`w-5 h-5 relative z-10 transition-colors ${
                activeTab === tab.id ? "text-primary" : "text-muted-foreground"
              }`}
            />
            <span
              className={`text-xs mt-1 relative z-10 transition-colors ${
                activeTab === tab.id ? "text-primary font-medium" : "text-muted-foreground"
              }`}
            >
              {tab.label}
            </span>
          </button>
        ))}
      </div>
    </nav>
  );
}
