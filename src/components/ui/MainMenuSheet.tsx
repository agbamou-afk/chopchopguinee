import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Menu, UserCircle2, BellRing, HelpCircle, FileText, LogIn, User, LogOut, Car } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Switch } from "@/components/ui/switch";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import logo from "@/assets/logo.png";

interface MenuButtonProps {
  isDriverMode?: boolean;
  onToggleDriverMode?: () => void;
  /** Render as a floating glass button (top-left overlay). */
  floating?: boolean;
  className?: string;
}

/**
 * Reusable hamburger menu trigger + side sheet, matching the menu inside
 * AppHeader. Use on screens that don't render AppHeader so users always have
 * the same menu access from any tab.
 */
export function MenuButton({
  isDriverMode,
  onToggleDriverMode,
  floating = false,
  className,
}: MenuButtonProps) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [isLoggedIn, setIsLoggedIn] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setIsLoggedIn(!!data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) =>
      setIsLoggedIn(!!s),
    );
    return () => sub.subscription.unsubscribe();
  }, []);

  const go = (path: string) => {
    setOpen(false);
    navigate(path);
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setOpen(false);
    toast({ title: "Déconnecté", description: "À bientôt sur CHOP CHOP" });
  };

  const items = [
    { icon: UserCircle2, label: "Profil", path: "/profile" },
    { icon: BellRing, label: "Notifications", path: "/settings/notifications" },
    { icon: HelpCircle, label: "Obtenir de l'aide", path: "/help" },
    { icon: FileText, label: "Mentions légales", path: "/legal" },
  ];

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <button
          aria-label="Menu"
          className={cn(
            floating
              ? "h-10 w-10 inline-flex items-center justify-center rounded-full bg-card/90 backdrop-blur border border-border/60 shadow-card text-foreground active:scale-95 transition"
              : "p-2 -ml-2 rounded-full hover:bg-muted transition-colors",
            className,
          )}
        >
          <Menu className="w-5 h-5" />
        </button>
      </SheetTrigger>
      <SheetContent side="left" className="w-80 drawer-warm relative">
        <div className="kente-stripe pointer-events-none absolute inset-x-0 top-0 h-[3px] opacity-80" aria-hidden />
        <SheetHeader>
          <SheetTitle className="sr-only">Menu CHOP CHOP</SheetTitle>
          <div className="flex flex-col items-center gap-2 pt-2">
            <img
              loading="eager"
              decoding="async"
              src={logo}
              alt="CHOP CHOP"
              className="h-24 w-auto object-contain"
            />
            <p className="text-xs font-medium text-muted-foreground italic">
              Tout, Part Tout, Pour Tout
            </p>
          </div>
        </SheetHeader>

        <div className="mt-6 space-y-1">
          {onToggleDriverMode && (
            <div className="flex items-center justify-between p-3 rounded-xl bg-muted/50">
              <div className="flex items-center gap-3">
                <div
                  className={`p-2 rounded-lg ${
                    isDriverMode ? "bg-secondary/20" : "bg-primary/10"
                  }`}
                >
                  <Car
                    className={`w-5 h-5 ${
                      isDriverMode ? "text-secondary" : "text-primary"
                    }`}
                  />
                </div>
                <div>
                  <p className="font-semibold text-foreground text-sm">
                    Mode Chauffeur
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {isDriverMode ? "Activé" : "Désactivé"}
                  </p>
                </div>
              </div>
              <Switch
                checked={!!isDriverMode}
                onCheckedChange={() => {
                  onToggleDriverMode();
                  setOpen(false);
                }}
              />
            </div>
          )}

          {items.map((item) => (
            <button
              key={item.label}
              onClick={() => go(item.path)}
              className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-muted transition-colors text-left"
            >
              <item.icon className="w-5 h-5 text-muted-foreground" />
              <span className="font-medium text-foreground text-sm">
                {item.label}
              </span>
            </button>
          ))}

          <div className="pt-4 border-t border-border mt-4 space-y-1">
            {!isLoggedIn ? (
              <>
                <button
                  onClick={() => go("/auth")}
                  className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-muted transition-colors text-left"
                >
                  <LogIn className="w-5 h-5 text-primary" />
                  <span className="font-medium text-foreground text-sm">
                    Se connecter
                  </span>
                </button>
                <button
                  onClick={() => go("/auth")}
                  className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-muted transition-colors text-left"
                >
                  <User className="w-5 h-5 text-primary" />
                  <span className="font-medium text-foreground text-sm">
                    S'inscrire
                  </span>
                </button>
              </>
            ) : (
              <button
                onClick={handleSignOut}
                className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-destructive/10 transition-colors text-left"
              >
                <LogOut className="w-5 h-5 text-destructive" />
                <span className="font-medium text-destructive text-sm">
                  Se déconnecter
                </span>
              </button>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}