import { motion, AnimatePresence } from "framer-motion";
import { MapPin, Navigation, X, Bike, Car, Clock, CreditCard } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";

interface RideBookingProps {
  type: "moto" | "toktok";
  onClose: () => void;
  onBook: () => void;
}

const rideOptions = {
  moto: {
    title: "Moto",
    icon: Bike,
    basePrice: 5000,
    pricePerKm: 1000,
    eta: "3-5 min",
  },
  toktok: {
    title: "TokTok",
    icon: Car,
    basePrice: 8000,
    pricePerKm: 1500,
    eta: "5-8 min",
  },
};

export function RideBooking({ type, onClose, onBook }: RideBookingProps) {
  const [pickup, setPickup] = useState("");
  const [destination, setDestination] = useState("");
  const option = rideOptions[type];
  const Icon = option.icon;

  const estimatedPrice = option.basePrice + option.pricePerKm * 5; // Assuming 5km

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 bg-background z-50 flex flex-col"
    >
      {/* Header */}
      <div className="gradient-primary p-4 pb-8 rounded-b-3xl">
        <div className="flex items-center justify-between mb-6">
          <button
            onClick={onClose}
            className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition-colors"
          >
            <X className="w-5 h-5 text-primary-foreground" />
          </button>
          <h1 className="text-lg font-bold text-primary-foreground">Réserver un {option.title}</h1>
          <div className="w-9" />
        </div>

        <div className="bg-white/10 backdrop-blur-sm rounded-2xl p-4">
          <div className="flex items-center gap-3 pb-4 border-b border-white/20">
            <div className="w-3 h-3 rounded-full bg-primary-foreground" />
            <input
              type="text"
              placeholder="Point de départ"
              value={pickup}
              onChange={(e) => setPickup(e.target.value)}
              className="flex-1 bg-transparent text-primary-foreground placeholder:text-white/60 focus:outline-none"
            />
            <MapPin className="w-5 h-5 text-white/60" />
          </div>
          <div className="flex items-center gap-3 pt-4">
            <div className="w-3 h-3 rounded-full bg-secondary" />
            <input
              type="text"
              placeholder="Destination"
              value={destination}
              onChange={(e) => setDestination(e.target.value)}
              className="flex-1 bg-transparent text-primary-foreground placeholder:text-white/60 focus:outline-none"
            />
            <Navigation className="w-5 h-5 text-white/60" />
          </div>
        </div>
      </div>

      {/* Map placeholder */}
      <div className="flex-1 bg-muted relative overflow-hidden">
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="text-center">
            <div className="w-16 h-16 rounded-full gradient-primary mx-auto flex items-center justify-center mb-3 shadow-soft animate-pulse-soft">
              <Icon className="w-8 h-8 text-primary-foreground" />
            </div>
            <p className="text-muted-foreground text-sm">Carte interactive</p>
          </div>
        </div>
        {/* Decorative elements */}
        <div className="absolute top-10 left-10 w-24 h-24 rounded-full bg-primary/10" />
        <div className="absolute bottom-20 right-10 w-32 h-32 rounded-full bg-secondary/10" />
      </div>

      {/* Bottom sheet */}
      <motion.div
        initial={{ y: 100 }}
        animate={{ y: 0 }}
        className="bg-card rounded-t-3xl p-6 shadow-elevated"
      >
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl gradient-primary">
              <Icon className="w-6 h-6 text-primary-foreground" />
            </div>
            <div>
              <h3 className="font-semibold text-foreground">{option.title}</h3>
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Clock className="w-4 h-4" />
                <span>{option.eta}</span>
              </div>
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold text-foreground">
              {new Intl.NumberFormat("fr-GN").format(estimatedPrice)} GNF
            </p>
            <p className="text-xs text-muted-foreground">Estimation</p>
          </div>
        </div>

        <div className="flex items-center gap-2 p-3 bg-muted rounded-xl mb-4">
          <CreditCard className="w-5 h-5 text-muted-foreground" />
          <span className="text-sm text-foreground">Portefeuille Chop Chop</span>
          <span className="ml-auto text-sm font-medium text-primary">Changer</span>
        </div>

        <Button
          onClick={onBook}
          className="w-full h-14 text-lg font-semibold gradient-primary hover:opacity-90 transition-opacity"
        >
          Confirmer la course
        </Button>
      </motion.div>
    </motion.div>
  );
}
