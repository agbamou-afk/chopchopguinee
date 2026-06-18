import { supabase } from "@/integrations/supabase/client";

/**
 * Repas order-bound messaging (Commerce Closing Patch).
 *
 * Thin client over the `food_order_threads` / `food_order_messages` tables.
 * Threads are opened via the `open_food_order_thread` security-definer RPC
 * which validates that the caller is the order's client or the restaurant
 * owner. RLS on the tables themselves restricts every read/write to the
 * thread's participants (client, restaurant owner, assigned courier) or an
 * admin moderator. No public/anon access.
 */

export type FoodOrderThreadType =
  | "restaurant_client_order"
  | "restaurant_courier_order";

export type FoodOrderSenderRole = "client" | "restaurant" | "courier" | "admin";

export interface FoodOrderMessage {
  id: string;
  thread_id: string;
  sender_user_id: string;
  sender_role: FoodOrderSenderRole;
  body: string;
  read_at: string | null;
  created_at: string;
}

export interface FoodOrderThread {
  id: string;
  food_order_id: string;
  restaurant_id: string;
  thread_type: FoodOrderThreadType;
  client_user_id: string;
  restaurant_owner_user_id: string;
  courier_user_id: string | null;
  last_message_at: string;
}

export const QUICK_REPLIES: Record<FoodOrderSenderRole, string[]> = {
  client: [
    "Bonjour, ma commande est-elle prête ?",
    "Merci",
    "Je suis à proximité",
  ],
  restaurant: [
    "Commande confirmée",
    "En préparation",
    "Prête pour retrait",
    "Un article est indisponible",
  ],
  courier: [
    "Je suis arrivé",
    "La commande est-elle prête ?",
    "Je récupère maintenant",
  ],
  admin: [],
};

type SB = typeof supabase;
// The generated types lag behind the new tables; cast at call sites only.
const sb = supabase as unknown as SB & {
  rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
};

export async function openOrderThread(
  foodOrderId: string,
  threadType: FoodOrderThreadType,
): Promise<string> {
  const { data, error } = await sb.rpc("open_food_order_thread", {
    _food_order_id: foodOrderId,
    _thread_type: threadType,
  });
  if (error) throw new Error(error.message);
  return data as string;
}

export async function listOrderMessages(threadId: string): Promise<FoodOrderMessage[]> {
  const { data, error } = await (supabase as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        eq: (c: string, v: unknown) => {
          order: (c: string, o: { ascending: boolean }) => Promise<{
            data: unknown;
            error: { message: string } | null;
          }>;
        };
      };
    };
  })
    .from("food_order_messages")
    .select("id, thread_id, sender_user_id, sender_role, body, read_at, created_at")
    .eq("thread_id", threadId)
    .order("created_at", { ascending: true });
  if (error) throw new Error(error.message);
  return (data as FoodOrderMessage[] | null) ?? [];
}

export async function sendOrderMessage(args: {
  threadId: string;
  senderRole: FoodOrderSenderRole;
  body: string;
}): Promise<void> {
  const { data: sess } = await supabase.auth.getSession();
  const uid = sess.session?.user.id;
  if (!uid) throw new Error("Connexion requise");
  const body = args.body.trim();
  if (!body) throw new Error("Message vide");
  if (body.length > 2000) throw new Error("Message trop long");
  const { error } = await (supabase as unknown as {
    from: (t: string) => {
      insert: (p: Record<string, unknown>) => Promise<{ error: { message: string } | null }>;
    };
  })
    .from("food_order_messages")
    .insert({
      thread_id: args.threadId,
      sender_user_id: uid,
      sender_role: args.senderRole,
      body,
    });
  if (error) throw new Error(error.message);
}

export async function markOrderMessagesRead(threadId: string): Promise<void> {
  const { data: sess } = await supabase.auth.getSession();
  const uid = sess.session?.user.id;
  if (!uid) return;
  await (supabase as unknown as {
    from: (t: string) => {
      update: (p: Record<string, unknown>) => {
        eq: (c: string, v: unknown) => {
          is: (c: string, v: unknown) => {
            neq: (c: string, v: unknown) => Promise<{ error: unknown }>;
          };
        };
      };
    };
  })
    .from("food_order_messages")
    .update({ read_at: new Date().toISOString() })
    .eq("thread_id", threadId)
    .is("read_at", null)
    .neq("sender_user_id", uid);
}

export async function listThreadsForUser(opts: {
  asRole: "client" | "restaurant_owner" | "courier";
  limit?: number;
}): Promise<FoodOrderThread[]> {
  const { data: sess } = await supabase.auth.getSession();
  const uid = sess.session?.user.id;
  if (!uid) return [];
  const col =
    opts.asRole === "client"
      ? "client_user_id"
      : opts.asRole === "restaurant_owner"
        ? "restaurant_owner_user_id"
        : "courier_user_id";
  const { data, error } = await (supabase as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        eq: (c: string, v: unknown) => {
          order: (c: string, o: { ascending: boolean }) => {
            limit: (n: number) => Promise<{ data: unknown; error: { message: string } | null }>;
          };
        };
      };
    };
  })
    .from("food_order_threads")
    .select("id, food_order_id, restaurant_id, thread_type, client_user_id, restaurant_owner_user_id, courier_user_id, last_message_at")
    .eq(col, uid)
    .order("last_message_at", { ascending: false })
    .limit(opts.limit ?? 50);
  if (error) throw new Error(error.message);
  return (data as FoodOrderThread[] | null) ?? [];
}