import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";

export type Wallet = {
  id: string;
  balance_gnf: number;
  held_gnf: number;
  currency: string;
  status: string;
};

export type WalletTransaction = {
  id: string;
  reference: string;
  type: string;
  status: string;
  amount_gnf: number;
  from_wallet_id: string | null;
  to_wallet_id: string | null;
  description: string | null;
  related_entity: string | null;
  created_at: string;
};

export type WalletProfile = {
  has_pin: boolean;
  full_name: string | null;
  phone: string | null;
};

export function useWallet(partyType: "client" | "driver" = "client") {
  const [userId, setUserId] = useState<string | null>(null);
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [transactions, setTransactions] = useState<WalletTransaction[]>([]);
  const [profile, setProfile] = useState<WalletProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

  const load = useCallback(async (uid: string | null) => {
    if (!uid) {
      setWallet(null);
      setTransactions([]);
      setProfile(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);

    const { data: w, error: wErr } = await supabase
      .from("wallets")
      .select("id, balance_gnf, held_gnf, currency, status")
      .eq("owner_user_id", uid)
      .eq("party_type", partyType)
      .maybeSingle();
    if (wErr) setError(wErr.message);
    setWallet(w as Wallet | null);

    const { data: p } = await supabase
      .from("profiles")
      .select("has_pin, full_name, phone")
      .eq("user_id", uid)
      .maybeSingle();
    setProfile(p as WalletProfile | null);

    if (w) {
      const { data: tx } = await supabase
        .from("wallet_transactions")
        .select("id, reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, description, related_entity, created_at")
        .or(`from_wallet_id.eq.${w.id},to_wallet_id.eq.${w.id}`)
        .order("created_at", { ascending: false })
        .limit(50);
      setTransactions((tx as WalletTransaction[] | null) ?? []);
    } else {
      setTransactions([]);
    }
    setLoading(false);
  }, [partyType]);

  useEffect(() => {
    let active = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      const uid = data.session?.user.id ?? null;
      setUserId(uid);
      load(uid);
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      const uid = session?.user.id ?? null;
      setUserId(uid);
      load(uid);
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, [load]);

  // Realtime: re-load on wallet or transaction changes for this user
  useEffect(() => {
    if (!userId) return;
    // Pause realtime when tab is hidden, offline, or low-data mode is on,
    // to spare metered Guinean mobile data and battery.
    const lowData = typeof window !== "undefined" && localStorage.getItem("cc:low_data_mode") === "1";
    const offline = typeof navigator !== "undefined" && navigator.onLine === false;
    const hidden = typeof document !== "undefined" && document.visibilityState === "hidden";
    if (lowData || offline || hidden) {
      // Still do a one-shot load so the UI is fresh; just don't subscribe.
      const onVisible = () => {
        if (document.visibilityState === "visible") load(userId);
      };
      document.addEventListener("visibilitychange", onVisible);
      return () => document.removeEventListener("visibilitychange", onVisible);
    }
    if (channelRef.current) {
      supabase.removeChannel(channelRef.current);
      channelRef.current = null;
    }
    const ch = supabase
      .channel(`wallet-${partyType}-${userId}-${Math.random().toString(36).slice(2)}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "wallets", filter: `owner_user_id=eq.${userId}` },
        () => load(userId),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "wallet_transactions", filter: `related_user_id=eq.${userId}` },
        () => load(userId),
      )
      .subscribe();
    channelRef.current = ch;
    return () => {
      supabase.removeChannel(ch);
      channelRef.current = null;
    };
  }, [userId, partyType, load]);

  const refresh = useCallback(() => load(userId), [load, userId]);
  const balance = wallet?.balance_gnf ?? 0;
  const held = wallet?.held_gnf ?? 0;
  const available = Math.max(0, balance - held);

  return { userId, wallet, balance, held, available, transactions, profile, loading, error, refresh };
}

export async function hashPin(pin: string, userId: string): Promise<string> {
  const data = new TextEncoder().encode(`chopchop-v1:${userId}:${pin}`);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}