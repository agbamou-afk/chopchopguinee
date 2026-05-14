import { motion } from "framer-motion";
import { Link, useNavigate } from "react-router-dom";
import {
  User,
  Settings,
  HelpCircle,
  Shield,
  LogOut,
  ChevronRight,
  Star,
  Car,
  Gift,
  ShieldCheck,
  MapPin,
  Gauge,
} from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { useAuth } from "@/contexts/AuthContext";
import { useAppEnv } from "@/contexts/AppEnvContext";
import { toast } from "@/hooks/use-toast";

interface ProfileViewProps {
  isDriverMode: boolean;
  onToggleDriverMode: () => void;
}

const menuItems: Array<{
  icon: typeof User;
  label: string;
  action: string;
  badge?: string;
  to?: string;
}> = [
  { icon: User, label: "Informations personnelles", action: "profile", to: "/profile" },
  { icon: Star, label: "Programme de fidélité", action: "loyalty", badge: "200 pts" },
  { icon: Gift, label: "Parrainer un ami", action: "referral" },
  { icon: Settings, label: "Paramètres", action: "settings", to: "/settings/notifications" },
  { icon: Shield, label: "Sécurité et confidentialité", action: "security", to: "/settings/privacy" },
  { icon: HelpCircle, label: "Aide et support", action: "help", to: "/help" },
];

export function ProfileView({ isDriverMode, onToggleDriverMode }: ProfileViewProps) {
  const { profile, user, roles, isAdmin, signOut } = useAuth();
  const { lowDataMode, setLowDataMode } = useAppEnv();
  const navigate = useNavigate();

  const isDriver = roles.includes("driver");
  const fullName =
    profile?.full_name?.trim() ||
    [profile?.first_name, profile?.last_name].filter(Boolean).join(" ").trim() ||
    profile?.display_name ||
    "Utilisateur CHOP CHOP";
  const initials = (
    (profile?.first_name?.[0] ?? "") + (profile?.last_name?.[0] ?? "")
  ).toUpperCase() || (user?.email?.[0]?.toUpperCase() ?? "C");
  const phone = profile?.phone ?? user?.phone ?? "Téléphone non renseigné";

  const handleLogout = async () => {
    await signOut();
    toast({ title: "Déconnecté", description: "À bientôt sur CHOP CHOP." });
    navigate("/auth", { replace: true });
  };

  const handleDriverToggle = () => {
    if (!isDriverMode && !isDriver) {
      toast({
        title: "Mode chauffeur indisponible",
        description: "Votre compte n'a pas encore le rôle chauffeur.",
      });
      return;
    }
    onToggleDriverMode();
  };

  return (
    <div className="max-w-md mx-auto">
      {/* Unified profile hero */}
      <div className="px-4 pt-4">
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="relative overflow-hidden bg-card rounded-[28px] shadow-soft border border-border/60 px-5 pt-5 pb-5"
        >
          <div className="pointer-events-none absolute -top-20 -right-16 w-56 h-56 rounded-full bg-primary/10 blur-3xl" aria-hidden />
          <div className="pointer-events-none absolute -bottom-24 -left-12 w-48 h-48 rounded-full bg-secondary/10 blur-3xl" aria-hidden />

          <div className="relative flex items-center gap-4">
            <button
              onClick={() => navigate("/profile")}
              className="w-20 h-20 rounded-2xl gradient-wallet text-primary-foreground flex items-center justify-center text-2xl font-extrabold ring-glow-primary shrink-0 overflow-hidden"
              aria-label="Voir mon profil"
            >
              {profile?.avatar_url ? (
                <img loading="lazy" decoding="async" src={profile.avatar_url} alt={fullName} className="w-full h-full object-cover" />
              ) : (
                initials
              )}
            </button>
            <div className="flex-1 min-w-0">
              <h2 className="text-lg font-extrabold text-foreground truncate">{fullName}</h2>
              <p className="text-xs text-muted-foreground truncate">{phone}</p>
              <div className="flex items-center gap-1 mt-1.5">
                <Star className="w-4 h-4 fill-secondary text-secondary" />
                <span className="text-sm font-bold text-foreground">—</span>
                <span className="text-xs text-muted-foreground">Nouveau membre</span>
              </div>
              <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
                <MapPin className="w-3 h-3 text-primary" />
                <span>Ratoma, Conakry</span>
              </div>
            </div>
          </div>
        </motion.div>
      </div>

      {/* Driver mode toggle */}
      <div className="px-4 mt-4 mb-4">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-card border border-border/60 flex items-center justify-between"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl gradient-wallet">
              <Car className="w-5 h-5 text-primary-foreground" />
            </div>
            <div>
              <p className="font-bold text-foreground">Mode Chauffeur</p>
              <p className="text-sm text-muted-foreground">
                {isDriver ? (isDriverMode ? "Activé" : "Désactivé") : "Rôle chauffeur requis"}
              </p>
            </div>
          </div>
          <Switch checked={isDriverMode} onCheckedChange={handleDriverToggle} disabled={!isDriver && !isDriverMode} />
        </motion.div>
      </div>

      {/* Low-data mode toggle */}
      <div className="px-4 mb-4">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-card border border-border/60 flex items-center justify-between"
        >
          <div className="flex items-center gap-3 min-w-0">
            <div className="p-2 rounded-xl bg-secondary/15">
              <Gauge className="w-5 h-5 text-secondary-foreground" />
            </div>
            <div className="min-w-0">
              <p className="font-bold text-foreground">Mode données réduites</p>
              <p className="text-sm text-muted-foreground truncate">
                Images allégées, cartes simplifiées, moins d'animations.
              </p>
            </div>
          </div>
          <Switch checked={lowDataMode} onCheckedChange={setLowDataMode} />
        </motion.div>
      </div>

      {/* Menu */}
      <div className="px-4 pb-28">
        <div className="bg-card rounded-2xl shadow-card border border-border/60 overflow-hidden">
          {menuItems.map((item, index) => (
            <motion.button
              key={item.action}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: index * 0.05 }}
              onClick={() => {
                if (item.to) {
                  navigate(item.to);
                } else {
                  toast({
                    title: item.label,
                    description: "Bientôt disponible.",
                  });
                }
              }}
              className="w-full flex items-center gap-4 p-4 hover:bg-muted/50 transition-colors border-b border-border last:border-b-0"
            >
              <div className="p-2 rounded-xl bg-muted">
                <item.icon className="w-5 h-5 text-muted-foreground" />
              </div>
              <span className="flex-1 text-left font-medium text-foreground">
                {item.label}
              </span>
              {item.badge && (
                <span className="text-xs font-medium text-primary bg-primary/10 px-2 py-1 rounded-full">
                  {item.badge}
                </span>
              )}
              <ChevronRight className="w-5 h-5 text-muted-foreground" />
            </motion.button>
          ))}
        </div>

        {/* Logout */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          onClick={handleLogout}
          aria-label="Se déconnecter"
          data-testid="logout-button"
          className="w-full flex items-center justify-center gap-2 mt-4 p-4 bg-destructive/10 text-destructive rounded-2xl font-medium hover:bg-destructive/20 transition-colors"
        >
          <LogOut className="w-5 h-5" />
          Se déconnecter
        </motion.button>

        {/* Admin link — only when the user actually has an admin role */}
        {isAdmin && (
          <Link
            to="/admin"
            className="w-full flex items-center justify-center gap-2 mt-3 p-3 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <ShieldCheck className="w-4 h-4" />
            Espace administrateur
          </Link>
        )}

        {/* Version */}
        <p className="text-center text-sm text-muted-foreground mt-6">
          Version 1.0.0
        </p>
      </div>
    </div>
  );
}
