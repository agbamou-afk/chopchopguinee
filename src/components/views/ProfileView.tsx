import { motion } from "framer-motion";
import { Link } from "react-router-dom";
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
} from "lucide-react";
import { Switch } from "@/components/ui/switch";

interface ProfileViewProps {
  isDriverMode: boolean;
  onToggleDriverMode: () => void;
}

const menuItems = [
  { icon: User, label: "Informations personnelles", action: "profile" },
  { icon: Star, label: "Programme de fidélité", action: "loyalty", badge: "200 pts" },
  { icon: Gift, label: "Parrainer un ami", action: "referral" },
  { icon: Settings, label: "Paramètres", action: "settings" },
  { icon: Shield, label: "Sécurité et confidentialité", action: "security" },
  { icon: HelpCircle, label: "Aide et support", action: "help" },
];

export function ProfileView({ isDriverMode, onToggleDriverMode }: ProfileViewProps) {
  return (
    <div className="max-w-md mx-auto">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="gradient-hero text-primary-foreground px-4 pt-6 pb-8 rounded-b-3xl"
      >
        <h1 className="text-xl font-bold mb-6">Mon Profil</h1>

        <div className="flex items-center gap-4">
          <div className="w-20 h-20 rounded-full bg-white/20 flex items-center justify-center text-3xl font-bold">
            MD
          </div>
          <div>
            <h2 className="text-xl font-bold">Mamadou Diallo</h2>
            <p className="text-sm opacity-80">+224 622 123 456</p>
            <div className="flex items-center gap-1 mt-1">
              <Star className="w-4 h-4 fill-secondary text-secondary" />
              <span className="text-sm font-medium">4.9</span>
              <span className="text-sm opacity-70">(127 avis)</span>
            </div>
          </div>
        </div>
      </motion.header>

      {/* Driver mode toggle */}
      <div className="px-4 -mt-4 mb-4">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-elevated flex items-center justify-between"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl gradient-primary">
              <Car className="w-5 h-5 text-primary-foreground" />
            </div>
            <div>
              <p className="font-semibold text-foreground">Mode Chauffeur</p>
              <p className="text-sm text-muted-foreground">
                {isDriverMode ? "Activé" : "Désactivé"}
              </p>
            </div>
          </div>
          <Switch checked={isDriverMode} onCheckedChange={onToggleDriverMode} />
        </motion.div>
      </div>

      {/* Menu */}
      <div className="px-4 pb-6">
        <div className="bg-card rounded-2xl shadow-card overflow-hidden">
          {menuItems.map((item, index) => (
            <motion.button
              key={item.action}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: index * 0.05 }}
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
          className="w-full flex items-center justify-center gap-2 mt-4 p-4 bg-destructive/10 text-destructive rounded-2xl font-medium hover:bg-destructive/20 transition-colors"
        >
          <LogOut className="w-5 h-5" />
          Se déconnecter
        </motion.button>

        {/* Admin link */}
        <Link
          to="/admin"
          className="w-full flex items-center justify-center gap-2 mt-3 p-3 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          <ShieldCheck className="w-4 h-4" />
          Espace administrateur
        </Link>

        {/* Version */}
        <p className="text-center text-sm text-muted-foreground mt-6">
          Version 1.0.0
        </p>
      </div>
    </div>
  );
}
