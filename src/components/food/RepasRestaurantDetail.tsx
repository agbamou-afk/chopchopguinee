import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Plus, Minus, ShoppingBag, Clock, X, CheckCircle2, MapPin, ShieldCheck, Truck, Package, BadgeCheck } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { formatGNF } from "@/lib/format";
import { PrimaryButton } from "@/components/ui/PrimaryButton";
import { toast } from "sonner";
import type { FoodMenuItem, FoodRestaurant, FoodFulfillment, FoodPaymentMethod } from "@/lib/repas/types";
import { listMenu } from "@/lib/repas/restaurants";
import { useRepasCart } from "@/lib/repas/cart";
import { createFoodOrder } from "@/lib/repas/orders";
import { useAuthGuard } from "@/hooks/useAuthGuard";
import { useWallet } from "@/hooks/useWallet";
import { ConversionGateSheet } from "@/components/onboarding/ConversionGateSheet";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";

interface Props {
  restaurant: FoodRestaurant;
  onClose: () => void;
}

type Stage = "menu" | "cart" | "checkout" | "confirmed";

function TrustChip({ icon: Icon, label, tone = "muted" }: { icon: typeof ShieldCheck; label: string; tone?: "primary" | "muted" | "warning" }) {
  const tones: Record<string, string> = {
    primary: "bg-primary/10 text-primary",
    muted: "bg-muted text-muted-foreground",
    warning: "bg-secondary/15 text-secondary-foreground",
  };
  return (
    <span className={cn("inline-flex items-center gap-1 px-2 py-1 rounded-full text-[11px] font-medium", tones[tone])}>
      <Icon className="w-3 h-3" />
      {label}
    </span>
  );
}

export function RepasRestaurantDetail({ restaurant, onClose }: Props) {
  const [menu, setMenu] = useState<FoodMenuItem[] | null>(null);
  const [stage, setStage] = useState<Stage>("menu");
  const [fulfillment, setFulfillment] = useState<FoodFulfillment>(
    restaurant.delivery_available ? "delivery" : "pickup",
  );
  const [paymentMethod, setPaymentMethod] = useState<FoodPaymentMethod>("cash");
  const [notes, setNotes] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [gateOpen, setGateOpen] = useState(false);

  const cart = useRepasCart();
  const { isLoggedIn, requireAuth } = useAuthGuard();
  const { wallet, available } = useWallet("client");

  useEffect(() => {
    let alive = true;
    listMenu(restaurant.id)
      .then((m) => alive && setMenu(m))
      .catch(() => alive && setMenu([]));
    return () => {
      alive = false;
    };
  }, [restaurant.id]);

  // Items in cart belonging to this restaurant
  const myCartLines = cart.restaurantId === restaurant.id ? cart.lines : [];
  const subtotal = myCartLines.reduce((s, l) => s + l.unitPriceGnf * l.qty, 0);
  const itemCount = myCartLines.reduce((s, l) => s + l.qty, 0);

  const qtyFor = (id: string) => myCartLines.find((l) => l.menuItemId === id)?.qty ?? 0;

  const add = (m: FoodMenuItem) => {
    cart.addItem(restaurant.id, restaurant.name, {
      menuItemId: m.id,
      name: m.name,
      unitPriceGnf: m.price_gnf,
      photoUrl: m.photo_url,
    });
  };
  const setQty = (id: string, delta: number) => {
    const current = qtyFor(id);
    cart.updateQty(id, Math.max(0, current + delta));
  };

  const grouped = useMemo(() => {
    if (!menu) return [] as { category: string; items: FoodMenuItem[] }[];
    const map = new Map<string, FoodMenuItem[]>();
    for (const item of menu) {
      const key = item.category ?? "Menu";
      const arr = map.get(key) ?? [];
      arr.push(item);
      map.set(key, arr);
    }
    return Array.from(map.entries()).map(([category, items]) => ({ category, items }));
  }, [menu]);

  const handlePlaceOrder = async () => {
    if (!isLoggedIn) {
      setGateOpen(true);
      return;
    }
    if (paymentMethod === "wallet" && available < subtotal) {
      toast.error("Solde CHOPWallet insuffisant");
      return;
    }
    setSubmitting(true);
    try {
      await createFoodOrder({
        restaurantId: restaurant.id,
        fulfillment,
        paymentMethod,
        notes: notes || undefined,
        deliveryAddress: fulfillment === "delivery" ? deliveryAddress || undefined : undefined,
        items: myCartLines.map((l) => ({
          menuItemId: l.menuItemId,
          name: l.name,
          unitPriceGnf: l.unitPriceGnf,
          qty: l.qty,
        })),
      });
      cart.clear();
      setStage("confirmed");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Impossible de passer la commande";
      toast.error(msg);
    } finally {
      setSubmitting(false);
    }
  };

  const cover = restaurant.cover_url || restaurant.avatar_url || "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600";

  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 24 }}
      className="fixed inset-0 z-[70] bg-background overflow-y-auto"
    >
      <div className="max-w-md mx-auto pb-40">
        {/* Hero */}
        <div className="relative h-44">
          <img loading="lazy" decoding="async" src={cover} alt={restaurant.name} className="w-full h-full object-cover" />
          <button
            onClick={onClose}
            className="absolute top-4 left-4 w-10 h-10 rounded-full bg-card/90 backdrop-blur flex items-center justify-center"
            aria-label="Retour"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
        </div>

        {/* Header card */}
        <div className="px-4 -mt-6 relative">
          <div className="bg-card rounded-2xl p-4 shadow-elevated">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <h1 className="text-xl font-bold text-foreground truncate">{restaurant.name}</h1>
                <p className="text-xs text-muted-foreground">
                  {restaurant.cuisine ?? "Cuisine locale"}
                  {restaurant.district ? ` · ${restaurant.district}` : ""}
                </p>
              </div>
              {restaurant.district && (
                <span className="shrink-0 inline-flex items-center gap-1 text-[11px] text-muted-foreground">
                  <MapPin className="w-3 h-3" />
                  {restaurant.district}
                </span>
              )}
            </div>

            {/* Trust chips — honest, no fake metrics */}
            <div className="flex flex-wrap gap-1.5 mt-3">
              <TrustChip
                icon={restaurant.is_open ? CheckCircle2 : Clock}
                label={restaurant.is_open ? "Ouvert" : "Fermé"}
                tone={restaurant.is_open ? "primary" : "muted"}
              />
              <TrustChip icon={Clock} label={`Préparation ~${restaurant.prep_time_min} min`} />
              {restaurant.delivery_available && <TrustChip icon={Truck} label="Livraison" />}
              {restaurant.pickup_available && <TrustChip icon={Package} label="Retrait" />}
              {restaurant.choppay_enabled && <TrustChip icon={ShieldCheck} label="CHOPPay" tone="primary" />}
              {restaurant.verification_state === "verified" && (
                <TrustChip icon={BadgeCheck} label="Vérifié" tone="primary" />
              )}
            </div>
          </div>
        </div>

        {/* Menu */}
        <section className="px-4 mt-6">
          {menu === null ? (
            <div className="space-y-3">
              {[0, 1, 2].map((i) => (
                <Skeleton key={i} className="h-24 rounded-2xl" />
              ))}
            </div>
          ) : menu.length === 0 ? (
            <div className="text-center py-10 text-sm text-muted-foreground">
              Le menu sera bientôt disponible.
            </div>
          ) : (
            grouped.map((group) => (
              <div key={group.category} className="mb-5">
                <h2 className="text-sm font-semibold text-foreground mb-2">{group.category}</h2>
                <div className="space-y-3">
                  {group.items.map((m) => {
                    const qty = qtyFor(m.id);
                    const disabled = !m.is_available || !restaurant.is_open;
                    return (
                      <div
                        key={m.id}
                        className={cn(
                          "bg-card rounded-2xl p-3 shadow-card flex gap-3",
                          disabled && "opacity-60",
                        )}
                      >
                        {m.photo_url && (
                          <img
                            loading="lazy"
                            decoding="async"
                            src={m.photo_url}
                            alt={m.name}
                            className="w-20 h-20 rounded-xl object-cover"
                          />
                        )}
                        <div className="flex-1 min-w-0">
                          <p className="font-semibold text-foreground text-sm">{m.name}</p>
                          {m.description && (
                            <p className="text-xs text-muted-foreground line-clamp-2">{m.description}</p>
                          )}
                          <p className="text-sm font-bold text-primary mt-1">{formatGNF(m.price_gnf)}</p>
                          {!m.is_available && (
                            <p className="text-[11px] text-muted-foreground mt-0.5">Indisponible</p>
                          )}
                        </div>
                        {disabled ? null : qty === 0 ? (
                          <button
                            onClick={() => add(m)}
                            className="self-end w-9 h-9 rounded-full gradient-primary text-primary-foreground flex items-center justify-center shadow-soft"
                            aria-label={`Ajouter ${m.name}`}
                          >
                            <Plus className="w-4 h-4" />
                          </button>
                        ) : (
                          <div className="self-end flex items-center gap-2 bg-muted rounded-full p-1">
                            <button
                              onClick={() => setQty(m.id, -1)}
                              className="w-7 h-7 rounded-full bg-card flex items-center justify-center"
                              aria-label="Retirer"
                            >
                              <Minus className="w-3.5 h-3.5" />
                            </button>
                            <span className="text-sm font-semibold w-5 text-center">{qty}</span>
                            <button
                              onClick={() => setQty(m.id, 1)}
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
              </div>
            ))
          )}
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

      {/* Cart / checkout sheet */}
      <AnimatePresence>
        {stage !== "menu" && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[60] bg-foreground/40 flex items-end justify-center"
            onClick={() => stage !== "confirmed" && !submitting && setStage("menu")}
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
                  <div className="w-16 h-16 mx-auto rounded-full bg-primary/10 flex items-center justify-center mb-4">
                    <CheckCircle2 className="w-9 h-9 text-primary" />
                  </div>
                  <h3 className="text-xl font-bold text-foreground mb-2">Commande envoyée</h3>
                  <p className="text-sm text-muted-foreground mb-1">
                    {restaurant.name} va confirmer votre commande.
                  </p>
                  <p className="text-xs text-muted-foreground mb-6">
                    {fulfillment === "delivery"
                      ? "Livraison à confirmer."
                      : `Prêt pour retrait dans ~${restaurant.prep_time_min} min.`}
                  </p>
                  <PrimaryButton fullWidth onClick={onClose}>
                    Terminer
                  </PrimaryButton>
                </div>
              ) : (
                <>
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-lg font-bold text-foreground">
                      {stage === "cart" ? "Votre panier" : "Confirmer la commande"}
                    </h3>
                    <button onClick={() => setStage("menu")} aria-label="Fermer" disabled={submitting}>
                      <X className="w-5 h-5" />
                    </button>
                  </div>

                  <div className="space-y-2 mb-4">
                    {myCartLines.map((l) => (
                      <div key={l.menuItemId} className="flex items-center gap-3 text-sm">
                        <span className="w-6 text-muted-foreground">{l.qty}×</span>
                        <span className="flex-1 text-foreground truncate">{l.name}</span>
                        <span className="font-medium text-foreground">{formatGNF(l.unitPriceGnf * l.qty)}</span>
                      </div>
                    ))}
                  </div>

                  {stage === "checkout" && (
                    <div className="space-y-4 mb-4">
                      {/* Fulfillment */}
                      <div>
                        <p className="text-xs font-medium text-muted-foreground mb-1.5">Mode</p>
                        <div className="grid grid-cols-2 gap-2">
                          <button
                            disabled={!restaurant.pickup_available}
                            onClick={() => setFulfillment("pickup")}
                            className={cn(
                              "h-12 rounded-xl text-sm font-medium border transition",
                              fulfillment === "pickup"
                                ? "bg-primary/10 border-primary text-primary"
                                : "bg-card border-border text-muted-foreground",
                              !restaurant.pickup_available && "opacity-40",
                            )}
                          >
                            <Package className="w-4 h-4 inline mr-1.5" /> Retrait
                          </button>
                          <button
                            disabled={!restaurant.delivery_available}
                            onClick={() => setFulfillment("delivery")}
                            className={cn(
                              "h-12 rounded-xl text-sm font-medium border transition",
                              fulfillment === "delivery"
                                ? "bg-primary/10 border-primary text-primary"
                                : "bg-card border-border text-muted-foreground",
                              !restaurant.delivery_available && "opacity-40",
                            )}
                          >
                            <Truck className="w-4 h-4 inline mr-1.5" /> Livraison
                          </button>
                        </div>
                        {fulfillment === "delivery" && (
                          <p className="text-[11px] text-muted-foreground mt-1.5">
                            Livraison à confirmer avec le restaurant.
                          </p>
                        )}
                      </div>

                      {fulfillment === "delivery" && (
                        <div>
                          <label className="text-xs font-medium text-muted-foreground block mb-1">
                            Adresse / repère
                          </label>
                          <input
                            value={deliveryAddress}
                            onChange={(e) => setDeliveryAddress(e.target.value)}
                            className="w-full bg-muted rounded-xl px-4 py-3 text-sm focus:outline-none"
                            placeholder="Quartier, repère utile…"
                          />
                        </div>
                      )}

                      {/* Payment method */}
                      <div>
                        <p className="text-xs font-medium text-muted-foreground mb-1.5">Paiement</p>
                        <div className="grid grid-cols-3 gap-2">
                          {(["cash", "wallet", "choppay"] as FoodPaymentMethod[]).map((pm) => {
                            const disabled = pm === "choppay" && !restaurant.choppay_enabled;
                            const label = pm === "cash" ? "Cash" : pm === "wallet" ? "Wallet" : "CHOPPay";
                            return (
                              <button
                                key={pm}
                                disabled={disabled}
                                onClick={() => setPaymentMethod(pm)}
                                className={cn(
                                  "h-11 rounded-xl text-xs font-medium border",
                                  paymentMethod === pm
                                    ? "bg-primary/10 border-primary text-primary"
                                    : "bg-card border-border text-muted-foreground",
                                  disabled && "opacity-40",
                                )}
                              >
                                {label}
                              </button>
                            );
                          })}
                        </div>
                        {paymentMethod === "wallet" && wallet && (
                          <p className="text-[11px] text-muted-foreground mt-1.5">
                            Solde disponible : {formatGNF(available)}
                          </p>
                        )}
                      </div>

                      <div>
                        <label className="text-xs font-medium text-muted-foreground block mb-1">
                          Notes (optionnel)
                        </label>
                        <input
                          value={notes}
                          onChange={(e) => setNotes(e.target.value)}
                          className="w-full bg-muted rounded-xl px-4 py-3 text-sm focus:outline-none"
                          placeholder="Sans piment, plus de sauce…"
                        />
                      </div>
                    </div>
                  )}

                  <div className="border-t border-border pt-3 space-y-1.5 text-sm mb-5">
                    <div className="flex justify-between font-bold text-base text-foreground">
                      <span>Sous-total</span>
                      <span>{formatGNF(subtotal)}</span>
                    </div>
                  </div>

                  {stage === "cart" ? (
                    <div className="space-y-2">
                      <PrimaryButton fullWidth onClick={() => setStage("checkout")}>
                        Continuer
                      </PrimaryButton>
                      <button
                        onClick={() => {
                          cart.clear();
                          setStage("menu");
                        }}
                        className="w-full text-xs text-muted-foreground py-2"
                      >
                        Vider le panier
                      </button>
                    </div>
                  ) : (
                    <PrimaryButton
                      fullWidth
                      onClick={() => {
                        if (!isLoggedIn) {
                          setGateOpen(true);
                          return;
                        }
                        requireAuth(handlePlaceOrder);
                      }}
                      disabled={submitting || itemCount === 0}
                    >
                      {submitting ? "Envoi…" : `Commander ${formatGNF(subtotal)}`}
                    </PrimaryButton>
                  )}
                </>
              )}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      <ConversionGateSheet
        open={gateOpen}
        intent="order"
        onOpenChange={setGateOpen}
        onExploreDriverDemo={() => setGateOpen(false)}
      />
    </motion.div>
  );
}
