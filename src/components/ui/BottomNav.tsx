import { Home, ShoppingBag, Wallet, User, ScanLine, type LucideIcon } from "lucide-react";
import { motion } from "framer-motion";
import { SteeringWheel } from "@/components/icons/SteeringWheel";
import type { ComponentType, SVGProps } from "react";

type IconType = LucideIcon | ComponentType<SVGProps<SVGSVGElement> & { size?: number | string }>;
type Tab = { id: string; icon: IconType; label: string };

interface BottomNavProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  isDriverMode?: boolean;
  onScanClick?: () => void;
}

const userTabs: Tab[] = [
  { id: "home", icon: Home, label: "Accueil" },
  { id: "orders", icon: ShoppingBag, label: "Activité" },
  { id: "wallet", icon: Wallet, label: "CHOPWallet" },
  { id: "profile", icon: User, label: "Compte" },
];

const driverTabs: Tab[] = [
  { id: "home", icon: Home, label: "Tableau" },
  { id: "orders", icon: SteeringWheel, label: "Courses" },
  { id: "profile", icon: User, label: "Profil" },
];

export function BottomNav({ activeTab, onTabChange, isDriverMode = false, onScanClick }: BottomNavProps) {
  const tabs = isDriverMode ? driverTabs : userTabs;
  // Insert center Scanner button only in client mode
  const left = tabs.slice(0, 2);
  const right = tabs.slice(2);

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-card/92 backdrop-blur-md border-t border-border/70 px-4 pt-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] z-50 shadow-soft">
      {/* Kente hairline — subtle brand seam at the very top edge */}
      <div className="kente-stripe pointer-events-none absolute inset-x-0 top-0 h-[2px] opacity-70" aria-hidden />
      {isDriverMode ? (
        <div className="max-w-md mx-auto grid grid-cols-3 items-center relative">
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
              className="-mt-7 w-[58px] h-[58px] rounded-full gradient-cta ring-[6px] ring-card flex items-center justify-center active:scale-95 transition-transform hover:scale-[1.03]"
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
  tab: Tab;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="relative flex flex-col items-center py-2 px-3 min-w-[60px] transition-colors"
    >
      {active && (
        <motion.div
          layoutId="activeTab"
          className="absolute inset-0 rounded-2xl bg-gradient-to-b from-primary/14 via-primary/6 to-transparent ring-1 ring-primary/12"
          style={{ boxShadow: "0 6px 18px -10px hsl(var(--primary) / 0.35)" }}
          transition={{ type: "tween", ease: [0.22, 1, 0.36, 1], duration: 0.32 }}
        />
      )}
      <tab.icon
        className={`w-[22px] h-[22px] relative z-10 transition-colors ${
          active ? "text-primary" : "text-muted-foreground"
        }`}
      />
      <span
        className={`text-[11px] mt-0.5 relative z-10 transition-colors tracking-wide ${
          active ? "text-primary font-semibold" : "text-muted-foreground"
        }`}
      >
        {tab.label}
      </span>
    </button>
  );
}
