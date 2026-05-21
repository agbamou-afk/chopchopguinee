import { useEffect, useMemo, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useWallet, type WalletTransaction } from "@/hooks/useWallet";
import type { ActivityItem, ActivityKind, ActivityStatus } from "./types";
import { txContext } from "@/lib/wallet/labels";
import {
  listBuyerInterests,
  INTEREST_KIND_LABEL,
  INTEREST_STATE_LABEL,
  type ListingInterest,
} from "@/lib/marche/interests";
import { listMyFoodOrders } from "@/lib/repas/orders";
import { FOOD_ORDER_STATE_LABEL, type FoodOrder } from "@/lib/repas/types";
import { listCustomerMissions, listCourierMissions } from "@/lib/missions/missions";
import {
  MISSION_STATE_LABEL,
  MISSION_TYPE_SHORT,
  isTerminalState,
  type Mission,
} from "@/lib/missions/types";
import { formatDistrictPair, detectDistrictInText, districtFor } from "@/lib/maps/zones";

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
  let title = "Mouvement WONGO Wallet";
  let subtitle: string | undefined = desc || undefined;
  let badge: ActivityItem["badge"];

  switch (tx.type) {
    case "topup":
      kind = "topup";
      title = "Recharge WONGO Wallet";
      subtitle = subtitle ?? "Solde crédité";
      break;
    case "payment":
      kind = isIncoming ? "transfer_in" : "merchant_payment";
      title = isIncoming ? "Paiement reçu" : "Paiement WONGO Pay";
      badge = "choppay";
      // Description shape from ChopPaySheet: "Paiement WONGO Pay · {merchant}".
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
      subtitle = subtitle ?? "Crédité sur WONGO Wallet";
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
    district: (() => {
      const c = txContext(tx);
      if (c.pickupArea && c.dropoffArea) return `${c.pickupArea} → ${c.dropoffArea}`;
      return c.pickupArea ?? c.dropoffArea ?? undefined;
    })(),
    merchantName: txContext(tx).merchantName ?? undefined,
    missionKind: txContext(tx).missionKind ?? undefined,
    meta: { txn: tx },
  };
}

function rideToActivity(ride: RideRow, role: "client" | "driver"): ActivityItem {
  const modeLabel = ride.mode === "toktok" ? "TokTok" : "Moto";
  const isDriver = role === "driver";
  const amount = isDriver ? (ride.driver_earning_gnf ?? 0) : -(ride.fare_gnf ?? 0);
  const status = statusFromRide(ride.status);
  const meta = (ride.metadata ?? {}) as Record<string, any>;
  const pickupText = meta.pickup_address ?? meta.pickup ?? null;
  const dropoffText = meta.dropoff_address ?? meta.destination ?? null;
  const a = pickupText ? detectDistrictInText(String(pickupText)) : null;
  const b = dropoffText ? detectDistrictInText(String(dropoffText)) : null;
  let district: string | undefined;
  if (a && b && a !== b) district = `${a} → ${b}`;
  else if (a || b) district = (a ?? b) as string;
  return {
    id: `ride:${ride.id}`,
    kind: "ride",
    title: isDriver ? `Course ${modeLabel} terminée` : `Course WONGO · ${modeLabel}`,
    subtitle: district ?? (status === "in_progress" ? "Course en cours" : status === "pending" ? "Recherche d'un chauffeur" : "Trajet terminé"),
    amount: status === "completed" ? amount : undefined,
    status,
    occurredAt: ride.completed_at ?? ride.created_at,
    reference: ride.id.slice(0, 8).toUpperCase(),
    entityId: ride.id,
    badge: status === "in_progress" ? "live" : undefined,
    district,
    missionKind: "moto",
    meta: { ride },
  };
}

/**
 * Aggregate ecosystem activity for the current user.
 *
 * Sources:
 *  - wallet_transactions for the user's `partyType` wallet (WONGO Wallet + WONGO Pay)
 *  - rides where user is client (or driver, depending on partyType)
 *
 * Repas / Marché order tables aren't yet wired; once they exist, plug them
 * into this hook so the rest of the UI stays untouched.
 */
export function useActivityFeed(partyType: "client" | "driver" = "client") {
  const { wallet, transactions, userId, loading: walletLoading, refresh: refreshWallet } = useWallet(partyType);
  const [rides, setRides] = useState<RideRow[]>([]);
  const [loadingRides, setLoadingRides] = useState(true);
  const [interests, setInterests] = useState<ListingInterest[]>([]);
  const [foodOrders, setFoodOrders] = useState<FoodOrder[]>([]);
  const [missions, setMissions] = useState<Mission[]>([]);

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

  useEffect(() => {
    if (!userId || partyType !== "client") {
      setInterests([]);
      return;
    }
    let alive = true;
    listBuyerInterests(userId, 30)
      .then((rows) => {
        if (alive) setInterests(rows);
      })
      .catch(() => alive && setInterests([]));
    return () => {
      alive = false;
    };
  }, [userId, partyType]);

  useEffect(() => {
    if (!userId || partyType !== "client") {
      setFoodOrders([]);
      return;
    }
    let alive = true;
    listMyFoodOrders(userId, 20)
      .then((rows) => alive && setFoodOrders(rows))
      .catch(() => alive && setFoodOrders([]));
    return () => {
      alive = false;
    };
  }, [userId, partyType]);

  useEffect(() => {
    if (!userId) {
      setMissions([]);
      return;
    }
    let alive = true;
    const fetcher = partyType === "driver" ? listCourierMissions : listCustomerMissions;
    fetcher(userId)
      .then((rows) => alive && setMissions(rows))
      .catch(() => alive && setMissions([]));
    return () => {
      alive = false;
    };
  }, [userId, partyType]);

  const items = useMemo<ActivityItem[]>(() => {
    const wId = wallet?.id ?? "";
    const txItems = wId
      ? transactions
          .map((t) => txnToActivity(t, wId))
          .filter((x): x is ActivityItem => x !== null)
      : [];
    const rideItems = rides.map((r) => rideToActivity(r, partyType));
    const interestItems: ActivityItem[] = interests.map((i) => ({
      id: `interest:${i.id}`,
      kind: "market_interest",
      title: INTEREST_KIND_LABEL[i.kind],
      subtitle: INTEREST_STATE_LABEL[i.state],
      status: i.state === "pending" ? "pending" : i.state === "declined" ? "cancelled" : "completed",
      occurredAt: i.updated_at ?? i.created_at,
      entityId: i.listing_id,
      meta: { interest: i },
    }));
    const foodItems: ActivityItem[] = foodOrders.map((o) => ({
      id: `food:${o.id}`,
      kind: "food_order",
      title: "Commande Repas",
      subtitle: FOOD_ORDER_STATE_LABEL[o.state],
      amount: -o.subtotal_gnf,
      status:
        o.state === "completed"
          ? "completed"
          : o.state === "cancelled"
            ? "cancelled"
            : o.state === "out_for_delivery" || o.state === "preparing" || o.state === "ready"
              ? "in_progress"
              : "pending",
      occurredAt: o.updated_at ?? o.created_at,
      entityId: o.id,
      district: o.delivery_lat != null && o.delivery_lng != null
        ? (districtFor({ lat: o.delivery_lat, lng: o.delivery_lng }) ?? undefined)
        : (detectDistrictInText(o.delivery_address) ?? undefined),
      missionKind: "repas",
      meta: { foodOrder: o },
    }));
    const missionItems: ActivityItem[] = missions.map((m) => {
      const kind: ActivityKind =
        m.type === "food_delivery"
          ? "food_order"
          : m.type === "marketplace_delivery"
            ? "market_order"
            : "ride";
      const status: ActivityStatus =
        m.state === "delivered"
          ? "completed"
          : m.state === "failed"
            ? "failed"
            : isTerminalState(m.state)
              ? "completed"
              : "in_progress";
      const pickupPt = m.pickup_lat != null && m.pickup_lng != null ? { lat: m.pickup_lat, lng: m.pickup_lng } : null;
      const dropPt = m.dropoff_lat != null && m.dropoff_lng != null ? { lat: m.dropoff_lat, lng: m.dropoff_lng } : null;
      const district = formatDistrictPair(pickupPt, dropPt)
        ?? detectDistrictInText(m.dropoff_address)
        ?? detectDistrictInText(m.pickup_address)
        ?? undefined;
      const missionKind: ActivityItem["missionKind"] =
        m.type === "food_delivery" ? "repas"
          : m.type === "marketplace_delivery" ? "marche"
            : m.type === "package_delivery" ? "envoyer"
              : "moto";
      return {
        id: `mission:${m.id}`,
        kind,
        title: `${MISSION_TYPE_SHORT[m.type]} · livraison`,
        subtitle: district ? `${MISSION_STATE_LABEL[m.state]} · ${district}` : MISSION_STATE_LABEL[m.state],
        amount: partyType === "driver" && m.state === "delivered" ? m.estimated_earning_gnf : undefined,
        status,
        occurredAt: m.updated_at ?? m.created_at,
        entityId: m.id,
        badge: status === "in_progress" ? "live" : undefined,
        district: district ?? undefined,
        missionKind,
        meta: { mission: m },
      };
    });
    return [...txItems, ...rideItems, ...interestItems, ...foodItems, ...missionItems].sort(
      (a, b) => new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime(),
    );
  }, [wallet?.id, transactions, rides, interests, foodOrders, missions, partyType]);

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