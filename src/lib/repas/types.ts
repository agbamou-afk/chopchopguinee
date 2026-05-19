export type FoodFulfillment = "pickup" | "delivery";
export type FoodOrderState =
  | "placed"
  | "confirmed"
  | "preparing"
  | "ready"
  | "out_for_delivery"
  | "completed"
  | "cancelled";
export type FoodPaymentMethod = "wallet" | "choppay" | "cash";

export interface FoodRestaurant {
  id: string;
  owner_user_id: string | null;
  slug: string;
  name: string;
  avatar_url: string | null;
  cover_url: string | null;
  district: string | null;
  cuisine: string | null;
  is_open: boolean;
  choppay_enabled: boolean;
  delivery_available: boolean;
  pickup_available: boolean;
  verification_state: string;
  prep_time_min: number;
  status: string;
}

export interface FoodMenuItem {
  id: string;
  restaurant_id: string;
  name: string;
  description: string | null;
  photo_url: string | null;
  price_gnf: number;
  category: string | null;
  is_available: boolean;
  prep_time_min: number | null;
  position: number;
}

export interface FoodOrder {
  id: string;
  user_id: string;
  restaurant_id: string;
  fulfillment: FoodFulfillment;
  state: FoodOrderState;
  payment_method: FoodPaymentMethod;
  subtotal_gnf: number;
  notes: string | null;
  delivery_address: string | null;
  created_at: string;
  updated_at: string;
}

export const FOOD_ORDER_STATE_LABEL: Record<FoodOrderState, string> = {
  placed: "Commande envoyée",
  confirmed: "Restaurant a confirmé",
  preparing: "En préparation",
  ready: "Prêt pour retrait",
  out_for_delivery: "En livraison",
  completed: "Livré",
  cancelled: "Annulée",
};
