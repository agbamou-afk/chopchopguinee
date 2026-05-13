import { motion } from "framer-motion";
import { Bell, Menu, Wallet, ChevronRight, User, HelpCircle, FileText, LogIn, Car, UserCircle2, LogOut } from "lucide-react";
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
}: AppHeaderProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setIsLoggedIn(!!data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      setIsLoggedIn(!!session);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const go = (path: string) => {
    setMenuOpen(false);
    navigate(path);
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setMenuOpen(false);
    toast({ title: "Déconnecté", description: "À bientôt sur CHOP CHOP" });
  };

  const formatted = new Intl.NumberFormat("fr-GN").format(amountValue);

  // Driver mode keeps a distinct accent (gold/secondary tint), client mode stays neutral.
  const cardClass = isDriverMode
    ? "bg-card rounded-3xl shadow-card px-5 pt-4 pb-5 border-2 border-secondary/40"
    : "bg-card rounded-3xl shadow-card px-5 pt-4 pb-5";

  const pillClass = isDriverMode
    ? "flex items-center gap-2 bg-secondary/15 hover:bg-secondary/25 transition-colors rounded-2xl pl-3 pr-2 py-2"
    : "flex items-center gap-2 bg-primary/10 hover:bg-primary/15 transition-colors rounded-2xl pl-3 pr-2 py-2";

  const pillIconColor = isDriverMode ? "text-secondary" : "text-primary";
  const avatarColor = isDriverMode ? "text-secondary" : "text-primary";

  const menuItems = [
    { icon: UserCircle2, label: "Profil", path: "/profile" },
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

          <img src={logo} alt="CHOP CHOP" className="h-20 w-auto object-contain" />

          <button
            className="p-2 -mr-2 rounded-full hover:bg-muted transition-colors relative"
            aria-label="Notifications"
            onClick={() => setNotifOpen(true)}
          >
            <Bell className="w-6 h-6 text-foreground" />
            {notificationCount > 0 && (
              <span className="absolute top-1 right-1 min-w-[18px] h-[18px] px-1 bg-destructive rounded-full text-[10px] font-bold text-destructive-foreground flex items-center justify-center">
                {notificationCount}
              </span>
            )}
          </button>

          <Sheet open={notifOpen} onOpenChange={setNotifOpen}>
            <SheetContent side="right" className="w-80">
              <SheetHeader>
                <SheetTitle>Notifications</SheetTitle>
              </SheetHeader>
              <div className="mt-6 flex flex-col items-center justify-center text-center py-12">
                <div className="w-14 h-14 rounded-full bg-muted flex items-center justify-center mb-3">
                  <Bell className="w-6 h-6 text-muted-foreground" />
                </div>
                <p className="font-semibold text-foreground text-sm">
                  Aucune notification
                </p>
                <p className="text-xs text-muted-foreground mt-1 max-w-[220px]">
                  Vos courses, paiements et messages CHOP CHOP apparaîtront ici.
                </p>
              </div>
            </SheetContent>
          </Sheet>
        </div>

        <div className="mt-4 flex items-center gap-3">
          <div className={`w-14 h-14 rounded-full bg-muted flex items-center justify-center text-xl font-bold ${avatarColor} shrink-0`}>
            {userInitial}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-base font-bold text-foreground truncate">
              Bonjour, {userName} ! 👋
            </p>
            <p className="text-sm text-muted-foreground truncate">
              {subtitle ?? (isDriverMode ? "Prêt à prendre des courses ?" : "Prêt à vous déplacer ?")}
            </p>
          </div>
          <button onClick={onAmountClick} className={pillClass}>
            <Wallet className={`w-5 h-5 ${pillIconColor}`} />
            <div className="text-left">
              <p className="text-sm font-bold text-foreground leading-tight">
                {formatted} GNF
              </p>
              <p className="text-[10px] text-muted-foreground leading-tight">
                {amountLabel}
              </p>
            </div>
            <ChevronRight className={`w-4 h-4 ${pillIconColor}`} />
          </button>
        </div>
      </motion.header>
    </div>
  );
}