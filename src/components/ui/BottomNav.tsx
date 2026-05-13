import { Home, ShoppingBag, Wallet, User, Car, ScanLine } from "lucide-react";
import { motion } from "framer-motion";

interface BottomNavProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  isDriverMode?: boolean;
  onScanClick?: () => void;
}

const userTabs = [
  { id: "home", icon: Home, label: "Accueil" },
  { id: "orders", icon: ShoppingBag, label: "Activité" },
  { id: "wallet", icon: Wallet, label: "Portefeuille" },
  { id: "profile", icon: User, label: "Compte" },
];

const driverTabs = [
  { id: "home", icon: Home, label: "Tableau" },
  { id: "orders", icon: Car, label: "Courses" },
  { id: "wallet", icon: Wallet, label: "Gains" },
  { id: "profile", icon: User, label: "Profil" },
];

export function BottomNav({ activeTab, onTabChange, isDriverMode = false, onScanClick }: BottomNavProps) {
  const tabs = isDriverMode ? driverTabs : userTabs;
  // Insert center Scanner button only in client mode
  const left = tabs.slice(0, 2);
  const right = tabs.slice(2);

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-card border-t border-border px-4 pt-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] z-50 shadow-elevated">
      {isDriverMode ? (
        <div className="max-w-md mx-auto grid grid-cols-4 items-center relative">
          {tabs.map((tab) => (
            <div key={tab.id} className="flex justify-center">
              <NavButton tab={tab} active={activeTab === tab.id} onClick={() => onTabChange(tab.id)} />
            </div>
          ))}
        </div>
      ) : (
        <div className="max-w-md mx-auto grid grid-cols-5 items-center relative">
          {left.map((tab) => (
            <div key={tab.id} className="flex justify-center">
              <NavButton tab={tab} active={activeTab === tab.id} onClick={() => onTabChange(tab.id)} />
            </div>
          ))}
          <div className="flex justify-center">
            <button
              onClick={onScanClick}
              aria-label="Scanner un QR CHOP CHOP"
              className="-mt-7 w-[58px] h-[58px] rounded-full bg-[hsl(145_55%_36%)] shadow-elevated ring-[6px] ring-card flex items-center justify-center active:scale-95 transition hover:shadow-soft"
            >
              <ScanLine className="w-6 h-6 text-primary-foreground" />
            </button>
          </div>
          {right.map((tab) => (
            <div key={tab.id} className="flex justify-center">
              <NavButton tab={tab} active={activeTab === tab.id} onClick={() => onTabChange(tab.id)} />
            </div>
          ))}
        </div>
      )}
    </nav>
  );
}

function NavButton({
  tab,
  active,
  onClick,
}: {
  tab: { id: string; icon: typeof Home; label: string };
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="relative flex flex-col items-center py-2 px-3 min-w-[60px]"
    >
      {active && (
        <motion.div
          layoutId="activeTab"
          className="absolute inset-0 bg-primary/10 rounded-xl"
          transition={{ type: "spring", bounce: 0.2, duration: 0.6 }}
        />
      )}
      <tab.icon
        className={`w-5 h-5 relative z-10 transition-colors ${
          active ? "text-primary" : "text-muted-foreground"
        }`}
      />
      <span
        className={`text-xs mt-1 relative z-10 transition-colors ${
          active ? "text-primary font-medium" : "text-muted-foreground"
        }`}
      >
        {tab.label}
      </span>
    </button>
  );
}
