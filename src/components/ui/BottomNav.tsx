import { Home, Receipt, LayoutGrid, User, type LucideIcon } from "lucide-react";
import { motion } from "framer-motion";
import { SteeringWheel } from "@/components/icons/SteeringWheel";
import type { ComponentType, SVGProps } from "react";

type IconType = LucideIcon | ComponentType<SVGProps<SVGSVGElement> & { size?: number | string }>;
type Tab = { id: string; icon: IconType; label: string };

interface BottomNavProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  isDriverMode?: boolean;
  /** @deprecated Kept for call-site compatibility; the center scanner FAB was removed. */
  onScanClick?: () => void;
}

/**
 * Approved Android 1.0 client shell: exactly four persistent destinations,
 * equal weighting, no floating center button. Payments (Orange Money) and
 * the scanner live inside the Services directory.
 */
const userTabs: Tab[] = [
  { id: "home", icon: Home, label: "Accueil" },
  { id: "services", icon: LayoutGrid, label: "Services" },
  { id: "orders", icon: Receipt, label: "Activité" },
  { id: "profile", icon: User, label: "Compte" },
];

const driverTabs: Tab[] = [
  { id: "home", icon: Home, label: "Tableau" },
  { id: "orders", icon: SteeringWheel, label: "Courses" },
  { id: "profile", icon: User, label: "Profil" },
];

export function BottomNav({ activeTab, onTabChange, isDriverMode = false }: BottomNavProps) {
  const tabs = isDriverMode ? driverTabs : userTabs;
  const cols = isDriverMode ? "grid-cols-3" : "grid-cols-4";

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-card/92 backdrop-blur-md border-t border-border/70 px-4 pt-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] z-50 shadow-soft">
      {/* Kente hairline — subtle brand seam at the very top edge */}
      <div className="kente-stripe pointer-events-none absolute inset-x-0 top-0 h-[2px] opacity-70" aria-hidden />
      <div className={`max-w-md mx-auto grid ${cols} items-center relative`}>
        {tabs.map((tab) => (
          <div key={tab.id} className="flex justify-center">
            <NavButton tab={tab} active={activeTab === tab.id} onClick={() => onTabChange(tab.id)} />
          </div>
        ))}
      </div>
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
      aria-current={active ? "page" : undefined}
      aria-label={tab.label}
      className="relative flex flex-col items-center justify-center py-2 px-2 min-w-[64px] min-h-[48px] transition-colors"
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
        className={`text-[11px] mt-0.5 relative z-10 transition-colors tracking-wide whitespace-nowrap ${
          active ? "text-primary font-semibold" : "text-muted-foreground"
        }`}
      >
        {tab.label}
      </span>
    </button>
  );
}
