import { useEffect, useMemo, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useWallet, type WalletTransaction } from "@/hooks/useWallet";
import type { ActivityItem, ActivityKind, ActivityStatus } from "./types";

type RideRow = {
  id: string;
  status: string;
  mode: string;
  fare_gnf: number;
  driver_earning_gnf: number | null;
  created_at: string;
  completed_at: string | null;
  metadata: Record<string, unknown> | null;
};

function statusFromTxn(s: string): ActivityStatus {
  if (s === "completed") return "completed";
  if (s === "pending" || s === "hold") return "pending";
  if (s === "failed") return "failed";
  if (s === "cancelled" || s === "reversed") return "cancelled";
  return "completed";
}

function statusFromRide(s: string): ActivityStatus {
  if (s === "completed") return "completed";
  if (s === "in_progress") return "in_progress";
  if (s === "pending") return "pending";
  if (s === "cancelled") return "cancelled";
  return "completed";
}

function txnToActivity(tx: WalletTransaction, walletId: string): ActivityItem | null {
  const isIncoming = tx.to_wallet_id === walletId;
  const signedAmount = isIncoming ? tx.amount_gnf : -tx.amount_gnf;
  const desc = tx.description ?? "";

  let kind: ActivityKind = "transfer_out";
  let title = "Mouvement CHOPWallet";
  let subtitle: string | undefined = desc || undefined;
  let badge: ActivityItem["badge"];

  switch (tx.type) {
    case "topup":
      kind = "topup";
      title = "Recharge CHOPWallet";
      subtitle = subtitle ?? "Solde crédité";
      break;
    case "payment":
      kind = isIncoming ? "transfer_in" : "merchant_payment";
      title = isIncoming ? "Paiement reçu" : "Paiement CHOPPay";
      badge = "choppay";
      // Description shape from ChopPaySheet: "Paiement CHOPPay · {merchant}".
      // Surface the merchant name as the subtitle so the timeline reads as a
      // proper merchant payment row instead of a raw description.
      if (!isIncoming && desc.includes("·")) {
        const tail = desc.split("·").slice(1).join("·").trim();
        if (tail) subtitle = tail;
      }
      break;
    case "transfer":
      kind = isIncoming ? "transfer_in" : "transfer_out";
      title = isIncoming ? "Transfert reçu" : "Transfert envoyé";
      break;
    case "refund":
      kind = "refund";
      title = "Remboursement";
      break;
    case "payout":
      kind = "payout";
      title = isIncoming ? "Versement chauffeur reçu" : "Versement chauffeur";
      subtitle = subtitle ?? "Crédité sur CHOPWallet";
      break;
    case "capture":
    case "release":
    case "hold":
      // Internal lifecycle events for ride payments — surfaced via the ride
      // entry instead, so we hide them from the timeline.
      return null;
    case "commission":
      // Pure platform-side accounting — not a user-visible event.
      return null;
    default:
      break;
  }

  return {
    id: `tx:${tx.id}`,
    kind,
    title,
    subtitle,
    amount: signedAmount,
    status: statusFromTxn(tx.status),
    occurredAt: tx.created_at,
    reference: tx.reference,
    entityId: tx.related_entity ?? undefined,
    badge,
    meta: { txn: tx },
  };
}

function rideToActivity(ride: RideRow, role: "client" | "driver"): ActivityItem {
  const modeLabel = ride.mode === "toktok" ? "TokTok" : "Moto";
  const isDriver = role === "driver";
  const amount = isDriver ? (ride.driver_earning_gnf ?? 0) : -(ride.fare_gnf ?? 0);
  const status = statusFromRide(ride.status);
  return {
    id: `ride:${ride.id}`,
    kind: "ride",
    title: isDriver ? `Course ${modeLabel} terminée` : `Course CHOP CHOP · ${modeLabel}`,
    subtitle: status === "in_progress" ? "Course en cours" : status === "pending" ? "Recherche d'un chauffeur" : "Trajet terminé",
    amount: status === "completed" ? amount : undefined,
    status,
    occurredAt: ride.completed_at ?? ride.created_at,
    reference: ride.id.slice(0, 8).toUpperCase(),
    entityId: ride.id,
    badge: status === "in_progress" ? "live" : undefined,
    meta: { ride },
  };
}

/**
 * Aggregate ecosystem activity for the current user.
 *
 * Sources:
 *  - wallet_transactions for the user's `partyType` wallet (CHOPWallet + CHOPPay)
 *  - rides where user is client (or driver, depending on partyType)
 *
 * Repas / Marché order tables aren't yet wired; once they exist, plug them
 * into this hook so the rest of the UI stays untouched.
 */
export function useActivityFeed(partyType: "client" | "driver" = "client") {
  const { wallet, transactions, userId, loading: walletLoading, refresh: refreshWallet } = useWallet(partyType);
  const [rides, setRides] = useState<RideRow[]>([]);
  const [loadingRides, setLoadingRides] = useState(true);

  const loadRides = useCallback(async (uid: string | null) => {
    if (!uid) {
      setRides([]);
      setLoadingRides(false);
      return;
    }
    setLoadingRides(true);
    const column = partyType === "driver" ? "driver_id" : "client_id";
    const { data } = await supabase
      .from("rides")
      .select("id,status,mode,fare_gnf,driver_earning_gnf,created_at,completed_at,metadata")
      .eq(column, uid)
      .order("created_at", { ascending: false })
      .limit(50);
    setRides((data as RideRow[] | null) ?? []);
    setLoadingRides(false);
  }, [partyType]);

  useEffect(() => {
    loadRides(userId);
  }, [userId, loadRides]);

  const items = useMemo<ActivityItem[]>(() => {
    const wId = wallet?.id ?? "";
    const txItems = wId
      ? transactions
          .map((t) => txnToActivity(t, wId))
          .filter((x): x is ActivityItem => x !== null)
      : [];
    const rideItems = rides.map((r) => rideToActivity(r, partyType));
    return [...txItems, ...rideItems].sort(
      (a, b) => new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime(),
    );
  }, [wallet?.id, transactions, rides, partyType]);

  const refresh = useCallback(() => {
    refreshWallet();
    loadRides(userId);
  }, [refreshWallet, loadRides, userId]);

  return {
    items,
    loading: walletLoading || loadingRides,
    refresh,
    isAuthenticated: !!userId,
  };
}