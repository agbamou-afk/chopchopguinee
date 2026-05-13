import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { Bell, Menu, Wallet, User, HelpCircle, FileText, LogIn, Car, UserCircle2, LogOut, BellRing, MapPin, Plus } from "lucide-react";
import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Switch } from "@/components/ui/switch";
import { notifications } from "@/lib/notifications";
import logo from "@/assets/logo.png";

interface AppHeaderProps {
  isDriverMode: boolean;
  onToggleDriverMode: () => void;
  userName?: string;
  userInitial?: string;
  subtitle?: string;
  amountLabel: string;
  amountValue: number;
  notificationCount?: number;
  onAmountClick?: () => void;
  location?: string;
  onRecharge?: () => void;
}

export function AppHeader({
  isDriverMode,
  onToggleDriverMode,
  userName = "Alpha",
  userInitial = "A",
  subtitle,
  amountLabel,
  amountValue,
  notificationCount = 0,
  onAmountClick,
  location = "Kaloum, Conakry",
  onRecharge,
}: AppHeaderProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [unread, setUnread] = useState(0);
  const navigate = useNavigate();

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setIsLoggedIn(!!data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      setIsLoggedIn(!!session);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    const refresh = () => setUnread(notifications.unreadCount());
    refresh();
    window.addEventListener("chopchop:notifications:update", refresh);
    return () => window.removeEventListener("chopchop:notifications:update", refresh);
  }, []);

  const totalBadge = unread + notificationCount;

  const go = (path: string) => {
    setMenuOpen(false);
    navigate(path);
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setMenuOpen(false);
    toast({ title: "Déconnecté", description: "À bientôt sur CHOP CHOP" });
  };

  const formatted = formatGNF(amountValue);

  const cardClass = isDriverMode
    ? "relative overflow-hidden bg-card rounded-[28px] shadow-soft px-5 pt-4 pb-5 border border-secondary/30"
    : "relative overflow-hidden bg-card rounded-[28px] shadow-soft px-5 pt-4 pb-5 border border-border/60";
  const avatarColor = isDriverMode ? "text-secondary" : "text-primary";

  const menuItems = [
    { icon: UserCircle2, label: "Profil", path: "/profile" },
    { icon: BellRing, label: "Notifications", path: "/settings/notifications" },
    { icon: HelpCircle, label: "Obtenir de l'aide", path: "/help" },
    { icon: FileText, label: "Mentions légales", path: "/legal" },
  ];

  return (
    <div className="px-4 pt-4">
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className={cardClass}
      >
        {/* Soft brand wash — anchors the hero without competing with content */}
        <div className="pointer-events-none absolute -top-24 -right-20 w-64 h-64 rounded-full bg-primary/10 blur-3xl" aria-hidden />
        <div className="pointer-events-none absolute -bottom-28 -left-16 w-56 h-56 rounded-full bg-secondary/10 blur-3xl" aria-hidden />

        <div className="flex items-center justify-between">
          <Sheet open={menuOpen} onOpenChange={setMenuOpen}>
            <SheetTrigger asChild>
              <button
                className="p-2 -ml-2 rounded-full hover:bg-muted transition-colors"
                aria-label="Menu"
              >
                <Menu className="w-6 h-6 text-foreground" />
              </button>
            </SheetTrigger>
            <SheetContent side="left" className="w-80">
              <SheetHeader>
                <SheetTitle className="sr-only">Menu CHOP CHOP</SheetTitle>
                <div className="flex flex-col items-center gap-2 pt-2">
                  <img src={logo} alt="CHOP CHOP" className="h-24 w-auto object-contain" />
                  <p className="text-xs font-medium text-muted-foreground italic">
                    Tout, Part Tout, Pour Tout
                  </p>
                </div>
              </SheetHeader>

              <div className="mt-6 space-y-1">
                {/* Driver mode toggle */}
                <div className="flex items-center justify-between p-3 rounded-xl bg-muted/50">
                  <div className="flex items-center gap-3">
                    <div className={`p-2 rounded-lg ${isDriverMode ? "bg-secondary/20" : "bg-primary/10"}`}>
                      <Car className={`w-5 h-5 ${isDriverMode ? "text-secondary" : "text-primary"}`} />
                    </div>
                    <div>
                      <p className="font-semibold text-foreground text-sm">Mode Chauffeur</p>
                      <p className="text-xs text-muted-foreground">
                        {isDriverMode ? "Activé" : "Désactivé"}
                      </p>
                    </div>
                  </div>
                  <Switch
                    checked={isDriverMode}
                    onCheckedChange={() => {
                      onToggleDriverMode();
                      setMenuOpen(false);
                    }}
                  />
                </div>

                {menuItems.map((item) => (
                  <button
                    key={item.label}
                    onClick={() => go(item.path)}
                    className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-muted transition-colors text-left"
                  >
                    <item.icon className="w-5 h-5 text-muted-foreground" />
                    <span className="font-medium text-foreground text-sm">{item.label}</span>
                  </button>
                ))}

                <div className="pt-4 border-t border-border mt-4 space-y-1">
                  {!isLoggedIn && (
                    <>
                      <button
                        onClick={() => go("/auth")}
                        className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-muted transition-colors text-left"
                      >
                        <LogIn className="w-5 h-5 text-primary" />
                        <span className="font-medium text-foreground text-sm">Se connecter</span>
                      </button>
                      <button
                        onClick={() => go("/auth")}
                        className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-muted transition-colors text-left"
                      >
                        <User className="w-5 h-5 text-primary" />
                        <span className="font-medium text-foreground text-sm">S'inscrire</span>
                      </button>
                    </>
                  )}
                  {isLoggedIn && (
                    <button
                      onClick={handleSignOut}
                      className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-destructive/10 transition-colors text-left"
                    >
                      <LogOut className="w-5 h-5 text-destructive" />
                      <span className="font-medium text-destructive text-sm">Se déconnecter</span>
                    </button>
                  )}
                </div>
              </div>
            </SheetContent>
          </Sheet>

          <img src={logo} alt="CHOP CHOP" className="h-16 w-auto object-contain" />

          <button
            className="p-2 -mr-2 rounded-full hover:bg-muted transition-colors relative"
            aria-label="Notifications"
            onClick={() => navigate("/notifications")}
          >
            <Bell className="w-6 h-6 text-foreground" />
            {totalBadge > 0 && (
              <span className="absolute top-1 right-1 min-w-[18px] h-[18px] px-1 bg-destructive rounded-full text-[10px] font-bold text-destructive-foreground flex items-center justify-center badge-bounce">
                {totalBadge > 9 ? "9+" : totalBadge}
              </span>
            )}
          </button>
        </div>

        {/* Greeting row */}
        <div className="mt-4 flex items-center gap-3 relative">
          <div className={`w-14 h-14 rounded-2xl bg-muted/70 flex items-center justify-center text-xl font-bold ${avatarColor} shrink-0 ring-1 ring-border/60`}>
            {userInitial}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[15px] font-bold text-foreground truncate leading-tight">
              Bonjour, {userName} 👋
            </p>
            <button className="mt-0.5 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors">
              <MapPin className="w-3 h-3 text-primary" />
              <span className="truncate max-w-[160px]">{location}</span>
            </button>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full rounded-full bg-success opacity-75 pulse-dot" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-success" />
            </span>
            <span className="text-[10px] font-medium text-muted-foreground">En ligne</span>
          </div>
        </div>

        {/* Wallet hero — green gradient, glass CTA, prominent balance */}
        <motion.button
          onClick={onAmountClick}
          whileTap={{ scale: 0.985 }}
          className="mt-4 w-full text-left rounded-2xl gradient-wallet text-primary-foreground p-4 relative overflow-hidden ring-glow-primary"
        >
          <div className="absolute inset-0 opacity-30 pointer-events-none">
            <div className="absolute -top-10 -right-10 w-40 h-40 rounded-full bg-white/10 blur-2xl" />
          </div>
          <div className="flex items-center justify-between relative">
            <div className="min-w-0">
              <div className="flex items-center gap-2 opacity-90">
                <Wallet className="w-4 h-4" />
                <span className="text-[11px] uppercase tracking-wider">{amountLabel}</span>
              </div>
              <p className="text-2xl font-extrabold mt-1 leading-none truncate">{formatted}</p>
              <p className="text-[11px] opacity-80 mt-1">Disponible · paiements sécurisés</p>
            </div>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onRecharge?.();
              }}
              className="shrink-0 inline-flex items-center gap-1.5 glass-surface text-primary-foreground rounded-full pl-2.5 pr-3 py-1.5 text-xs font-semibold hover:bg-white/25 transition-colors"
            >
              <Plus className="w-3.5 h-3.5" />
              Recharger
            </button>
          </div>
        </motion.button>
      </motion.header>
    </div>
  );
}