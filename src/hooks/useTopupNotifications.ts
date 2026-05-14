import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { notifyWalletEvent } from "@/lib/notifications/walletNotifier";
import { formatGNF } from "@/lib/format";

/**
 * Subscribes the authenticated user to realtime status changes on their
 * topup_requests rows and emits in-app notifications + toasts.
 * Mount once near the app root.
 */
export function useTopupNotifications() {
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

  useEffect(() => {
    let active = true;
    let currentUid: string | null = null;

    const subscribe = (uid: string | null) => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
      if (!uid) return;
      currentUid = uid;
      const ch = supabase
        .channel(`topup-notif-${uid}`)
        .on(
          "postgres_changes",
          {
            event: "UPDATE",
            schema: "public",
            table: "topup_requests",
            filter: `client_user_id=eq.${uid}`,
          },
          (payload: any) => {
            const before = payload.old?.status;
            const after = payload.new?.status;
            if (!after || before === after) return;
            const amount = Number(payload.new?.amount_gnf ?? 0);
            const ref = payload.new?.reference ?? "";
            const id = payload.new?.id ?? ref;

            // Standardized dedup'd wallet event flow.
            if (after === "credited" || after === "confirmed") {
              void notifyWalletEvent({
                eventId: `topup:${id}:credited`,
                event: "topup_credited",
                amountGnf: amount,
                reference: ref,
                userId: uid,
              });
              return;
            }

            // Other status transitions stay as a single toast (no fan-out).
            if (after === "needs_review") {
              toast.message("Recharge en vérification", {
                description: `Votre recharge ${ref} est en cours de vérification.`,
                id: `topup:${id}:needs_review`,
              });
            } else if (after === "expired") {
              toast.error("Recharge expirée", {
                description: `La recharge ${ref} a expiré.`,
                id: `topup:${id}:expired`,
              });
            } else if (after === "cancelled") {
              toast("Recharge annulée", {
                description: `La recharge ${ref} a été annulée.`,
                id: `topup:${id}:cancelled`,
              });
            }
            void formatGNF; // keep import used
          },
        )
        .subscribe();
      channelRef.current = ch;
    };

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      subscribe(data.session?.user.id ?? null);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      const uid = session?.user.id ?? null;
      if (uid !== currentUid) subscribe(uid);
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
    };
  }, []);
}