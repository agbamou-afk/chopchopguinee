import { motion } from "framer-motion";
import { LucideIcon } from "lucide-react";

interface ServiceCardProps {
  icon: LucideIcon;
  title: string;
  description: string;
  gradient?: "primary" | "secondary" | "destructive";
  onClick?: () => void;
}

const gradientStyles = {
  primary: "gradient-primary",
  secondary: "gradient-secondary",
  destructive: "bg-destructive",
};

export function ServiceCard({ icon: Icon, title, description, gradient = "primary", onClick }: ServiceCardProps) {
  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="flex flex-col items-center p-4 rounded-2xl bg-card shadow-card hover:shadow-elevated transition-shadow duration-300 w-full"
    >
      <div className={`p-3 rounded-xl ${gradientStyles[gradient]} mb-3`}>
        <Icon className="w-6 h-6 text-primary-foreground" />
      </div>
      <h3 className="font-semibold text-foreground text-sm">{title}</h3>
      <p className="text-xs text-muted-foreground mt-1">{description}</p>
    </motion.button>
  );
}
