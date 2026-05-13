import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { notifications } from "@/lib/notifications";
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
            let title = "";
            let body = "";
            switch (after) {
              case "credited":
              case "confirmed":
                title = "Recharge créditée";
                body = `${formatGNF(amount)} ajoutés à votre portefeuille (${ref}).`;
                toast.success(title, { description: body });
                break;
              case "needs_review":
                title = "Recharge en vérification";
                body = `Votre recharge ${ref} est en cours de vérification par notre équipe.`;
                toast.message(title, { description: body });
                break;
              case "expired":
                title = "Recharge expirée";
                body = `La recharge ${ref} a expiré sans réception du paiement.`;
                toast.error(title, { description: body });
                break;
              case "cancelled":
                title = "Recharge annulée";
                body = `La recharge ${ref} a été annulée.`;
                toast(title, { description: body });
                break;
              default:
                return;
            }
            notifications.push({ kind: "wallet", title, body });
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