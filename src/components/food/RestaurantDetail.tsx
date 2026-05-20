import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Plus, Minus, ShoppingBag, Clock, Star, MapPin, X, CheckCircle2, LocateFixed, Loader2 } from "lucide-react";
import { useMemo, useState } from "react";
import { formatGNF } from "@/lib/format";
import { PrimaryButton } from "@/components/ui/PrimaryButton";
import { toast } from "sonner";

export interface MenuItem {
  id: string;
  name: string;
  description: string;
  price: number;
  image?: string;
}

export interface Restaurant {
  name: string;
  image: string;
  rating: number;
  deliveryTime: string;
  distance: string;
  category: string;
  menu: MenuItem[];
}

interface Props {
  restaurant: Restaurant;
  onClose: () => void;
}

type Stage = "menu" | "cart" | "checkout" | "confirmed";

const DELIVERY_FEE = 8000;

export function RestaurantDetail({ restaurant, onClose }: Props) {
  const [cart, setCart] = useState<Record<string, number>>({});
  const [stage, setStage] = useState<Stage>("menu");
  const [address, setAddress] = useState("Kipé, Conakry");
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [locating, setLocating] = useState(false);

  const items = useMemo(
    () =>
      Object.entries(cart)
        .map(([id, qty]) => {
          const item = restaurant.menu.find((m) => m.id === id);
          return item ? { ...item, qty } : null;
        })
        .filter((x): x is MenuItem & { qty: number } => x !== null),
    [cart, restaurant.menu],
  );

  const subtotal = items.reduce((s, i) => s + i.price * i.qty, 0);
  const total = subtotal > 0 ? subtotal + DELIVERY_FEE : 0;
  const itemCount = items.reduce((s, i) => s + i.qty, 0);

  const inc = (id: string) => setCart((c) => ({ ...c, [id]: (c[id] ?? 0) + 1 }));
  const dec = (id: string) =>
    setCart((c) => {
      const next = { ...c };
      const v = (next[id] ?? 0) - 1;
      if (v <= 0) delete next[id];
      else next[id] = v;
      return next;
    });

  const placeOrder = () => {
    setStage("confirmed");
    toast.success("Commande confirmée !");
    if (coords) {
      // Coordinates captured with the order (demo flow keeps state local).
      console.info("[repas demo] delivery coords", coords);
    }
  };

  const useCurrentLocation = () => {
    if (!("geolocation" in navigator)) {
      toast.error("Géolocalisation non disponible sur cet appareil.");
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords;
        setCoords({ lat: latitude, lng: longitude });
        setAddress(`Position actuelle (${latitude.toFixed(5)}, ${longitude.toFixed(5)})`);
        setLocating(false);
        toast.success("Position actuelle sélectionnée");
      },
      () => {
        setLocating(false);
        toast("Position non autorisée. Entrez l’adresse manuellement.");
      },
      { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 },
    );
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 24 }}
      className="fixed inset-0 z-[70] bg-background overflow-y-auto"
    >
      <div className="max-w-md mx-auto pb-40">
        {/* Hero */}
        <div className="relative h-48">
          <img loading="lazy" decoding="async" src={restaurant.image} alt={restaurant.name} className="w-full h-full object-cover" />
          <button
            onClick={onClose}
            className="absolute top-4 left-4 w-10 h-10 rounded-full bg-card/90 backdrop-blur flex items-center justify-center"
            aria-label="Retour"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
        </div>

        {/* Info */}
        <div className="px-4 -mt-6 relative">
          <div className="bg-card rounded-2xl p-4 shadow-elevated">
            <h1 className="text-xl font-bold text-foreground">{restaurant.name}</h1>
            <p className="text-xs text-muted-foreground">{restaurant.category}</p>
            <div className="flex items-center gap-3 mt-2 text-xs text-muted-foreground">
              <span className="flex items-center gap-1">
                <Star className="w-3.5 h-3.5 fill-secondary text-secondary" /> {restaurant.rating}
              </span>
              <span className="flex items-center gap-1">
                <Clock className="w-3.5 h-3.5" /> {restaurant.deliveryTime}
              </span>
              <span className="flex items-center gap-1">
                <MapPin className="w-3.5 h-3.5" /> {restaurant.distance}
              </span>
            </div>
          </div>
        </div>

        {/* Menu */}
        <section className="px-4 mt-6">
          <h2 className="text-base font-semibold text-foreground mb-3">Menu</h2>
          <div className="space-y-3">
            {restaurant.menu.map((m) => {
              const qty = cart[m.id] ?? 0;
              return (
                <div key={m.id} className="bg-card rounded-2xl p-3 shadow-card flex gap-3">
                  {m.image && (
                    <img loading="lazy" decoding="async" src={m.image} alt={m.name} className="w-20 h-20 rounded-xl object-cover" />
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-foreground text-sm">{m.name}</p>
                    <p className="text-xs text-muted-foreground line-clamp-2">{m.description}</p>
                    <p className="text-sm font-bold text-primary mt-1">{formatGNF(m.price)}</p>
                  </div>
                  {qty === 0 ? (
                    <button
                      onClick={() => inc(m.id)}
                      className="self-end w-9 h-9 rounded-full gradient-primary text-primary-foreground flex items-center justify-center shadow-soft"
                      aria-label={`Ajouter ${m.name}`}
                    >
                      <Plus className="w-4 h-4" />
                    </button>
                  ) : (
                    <div className="self-end flex items-center gap-2 bg-muted rounded-full p-1">
                      <button
                        onClick={() => dec(m.id)}
                        className="w-7 h-7 rounded-full bg-card flex items-center justify-center"
                        aria-label="Retirer"
                      >
                        <Minus className="w-3.5 h-3.5" />
                      </button>
                      <span className="text-sm font-semibold w-5 text-center">{qty}</span>
                      <button
                        onClick={() => inc(m.id)}
                        className="w-7 h-7 rounded-full gradient-primary text-primary-foreground flex items-center justify-center"
                        aria-label="Ajouter"
                      >
                        <Plus className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      </div>

      {/* Floating cart bar — Conakry Contemporary */}
      <AnimatePresence>
        {itemCount > 0 && stage === "menu" && (
          <motion.div
            initial={{ y: 96, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 96, opacity: 0 }}
            transition={{ type: "spring", stiffness: 320, damping: 28 }}
            className="fixed left-0 right-0 z-40 px-4 pointer-events-none"
            style={{ bottom: "calc(env(safe-area-inset-bottom, 0px) + 16px)" }}
          >
            <button
              onClick={() => setStage("cart")}
              className="pointer-events-auto mx-auto w-full max-w-md flex items-center justify-between gap-3 bg-card border border-border/60 rounded-2xl pl-4 pr-2 py-2 shadow-elevated"
            >
              <span className="flex items-center gap-2.5 min-w-0">
                <span className="w-9 h-9 rounded-xl bg-primary/10 text-primary flex items-center justify-center shrink-0">
                  <ShoppingBag className="w-4 h-4" />
                </span>
                <span className="flex flex-col items-start min-w-0">
                  <span className="text-[11px] text-muted-foreground leading-tight">
                    {itemCount} article{itemCount > 1 ? "s" : ""}
                  </span>
                  <span className="text-sm font-bold text-foreground leading-tight truncate">
                    {formatGNF(subtotal)}
                  </span>
                </span>
              </span>
              <span className="shrink-0 gradient-primary text-primary-foreground rounded-xl px-4 py-2.5 text-sm font-semibold shadow-soft">
                Voir le panier
              </span>
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Cart sheet */}
      <AnimatePresence>
        {stage !== "menu" && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[60] bg-foreground/40 flex items-end justify-center"
            onClick={() => stage !== "confirmed" && setStage("menu")}
          >
            <motion.div
              initial={{ y: 400 }}
              animate={{ y: 0 }}
              exit={{ y: 400 }}
              transition={{ type: "spring", stiffness: 300, damping: 30 }}
              onClick={(e) => e.stopPropagation()}
              className="w-full max-w-md bg-card rounded-t-3xl p-5 max-h-[85vh] overflow-y-auto"
            >
              {stage === "confirmed" ? (
                <div className="text-center py-6">
                  <div className="w-16 h-16 mx-auto rounded-full bg-brand-green-muted flex items-center justify-center mb-4">
                    <CheckCircle2 className="w-9 h-9 text-primary" />
                  </div>
                  <h3 className="text-xl font-bold text-foreground mb-2">Commande confirmée</h3>
                  <p className="text-sm text-muted-foreground mb-1">
                    {restaurant.name} prépare votre commande.
                  </p>
                  <p className="text-xs text-muted-foreground mb-6">
                    Livraison estimée : {restaurant.deliveryTime}
                  </p>
                  <PrimaryButton fullWidth onClick={onClose}>Terminer</PrimaryButton>
                </div>
              ) : (
                <>
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-lg font-bold text-foreground">
                      {stage === "cart" ? "Votre panier" : "Confirmer la commande"}
                    </h3>
                    <button onClick={() => setStage("menu")} aria-label="Fermer">
                      <X className="w-5 h-5" />
                    </button>
                  </div>

                  <div className="space-y-2 mb-4">
                    {items.map((i) => (
                      <div key={i.id} className="flex items-center gap-3 text-sm">
                        <span className="w-6 text-muted-foreground">{i.qty}×</span>
                        <span className="flex-1 text-foreground">{i.name}</span>
                        <span className="font-medium text-foreground">{formatGNF(i.price * i.qty)}</span>
                      </div>
                    ))}
                  </div>

                  {stage === "checkout" && (
                    <div className="mb-4">
                      <label className="text-xs font-medium text-muted-foreground block mb-1">
                        Adresse de livraison
                      </label>
                      <input
                        value={address}
                        onChange={(e) => {
                          setAddress(e.target.value);
                          if (coords) setCoords(null);
                        }}
                        className="w-full bg-muted rounded-xl px-4 py-3 text-sm focus:outline-none"
                        placeholder="Quartier, repère utile…"
                      />
                      <button
                        type="button"
                        onClick={useCurrentLocation}
                        disabled={locating}
                        className={`mt-2 inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[12px] font-medium border transition ${
                          coords
                            ? "bg-primary/10 border-primary/30 text-primary"
                            : "bg-card border-border text-muted-foreground hover:text-foreground"
                        } ${locating ? "opacity-60" : ""}`}
                      >
                        {locating ? (
                          <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        ) : (
                          <LocateFixed className="w-3.5 h-3.5" />
                        )}
                        {coords ? "Position actuelle utilisée" : "Utiliser ma position actuelle"}
                      </button>
                    </div>
                  )}

                  <div className="border-t border-border pt-3 space-y-1.5 text-sm mb-5">
                    <div className="flex justify-between text-muted-foreground">
                      <span>Sous-total</span>
                      <span>{formatGNF(subtotal)}</span>
                    </div>
                    <div className="flex justify-between text-muted-foreground">
                      <span>Livraison</span>
                      <span>{formatGNF(DELIVERY_FEE)}</span>
                    </div>
                    <div className="flex justify-between font-bold text-base text-foreground pt-1">
                      <span>Total</span>
                      <span>{formatGNF(total)}</span>
                    </div>
                  </div>

                  {stage === "cart" ? (
                    <PrimaryButton fullWidth onClick={() => setStage("checkout")}>
                      Continuer
                    </PrimaryButton>
                  ) : (
                    <PrimaryButton fullWidth onClick={placeOrder}>
                      Payer {formatGNF(total)}
                    </PrimaryButton>
                  )}
                </>
              )}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
