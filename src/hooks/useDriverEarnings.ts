import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface EarningTxn {
  id: string;
  reference: string;
  type: string;
  amount_gnf: number;
  related_entity: string | null;
  description: string | null;
  created_at: string;
}

export interface DayBucket {
  day: string; // 3-letter
  amount: number;
  rides: number;
  date: string; // ISO date
}

export interface DriverEarningsState {
  loading: boolean;
  todayGnf: number;
  weekGnf: number;
  weeklyBuckets: DayBucket[];
  completedToday: number;
  completedWeek: number;
  cashCollectedWeek: number;
  commissionDueWeek: number;
  cashDebtGnf: number;
  debtLimitGnf: number;
  recent: EarningTxn[];
  missionEarningsAvailable: boolean;
  refetch: () => Promise<void>;
}

const DAY_LABELS = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];

function startOfWeek(d: Date): Date {
  const r = new Date(d);
  r.setHours(0, 0, 0, 0);
  const dow = r.getDay(); // 0=Sun
  const diff = (dow + 6) % 7; // shift to Monday
  r.setDate(r.getDate() - diff);
  return r;
}

export function useDriverEarnings(): DriverEarningsState {
  const { user } = useAuth();
  const [state, setState] = useState<Omit<DriverEarningsState, "refetch">>({
    loading: true,
    todayGnf: 0,
    weekGnf: 0,
    weeklyBuckets: [],
    completedToday: 0,
    completedWeek: 0,
    cashCollectedWeek: 0,
    commissionDueWeek: 0,
    cashDebtGnf: 0,
    debtLimitGnf: 0,
    recent: [],
    missionEarningsAvailable: false,
  });

  const refetch = useCallback(async () => {
    if (!user) return;
    setState((s) => ({ ...s, loading: true }));
    const weekStart = startOfWeek(new Date());
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);

    // Source of truth: driver wallet + wallet_transactions ledger.
    // rides.driver_earning_gnf is intentionally NOT queried as a primary
    // dashboard metric — it drifts from the credited ledger.
    const { data: walletRow } = await supabase
      .from("wallets")
      .select("id")
      .eq("owner_user_id", user.id)
      .eq("party_type", "driver")
      .maybeSingle();
    const driverWalletId = (walletRow as { id: string } | null)?.id ?? null;

    const [txRes, ledgerRes, profileRes] = await Promise.all([
      driverWalletId
        ? supabase
            .from("wallet_transactions")
            .select("id,reference,type,amount_gnf,related_entity,description,created_at,status,to_wallet_id")
            .eq("to_wallet_id", driverWalletId)
            .eq("status", "completed")
            .eq("type", "ride_earning")
            .gt("amount_gnf", 0)
            .gte("created_at", weekStart.toISOString())
            .order("created_at", { ascending: false })
            .limit(500)
        : Promise.resolve({ data: [] as Array<{
            id: string; reference: string; type: string; amount_gnf: number;
            related_entity: string | null; description: string | null;
            created_at: string;
          }> }),
      supabase
        .from("driver_cash_ledger")
        .select("cash_collected_gnf,commission_owed_gnf,settled_amount_gnf,created_at")
        .eq("driver_id", user.id)
        .gte("created_at", weekStart.toISOString()),
      supabase
        .from("driver_profiles")
        .select("cash_debt_gnf,debt_limit_gnf")
        .eq("user_id", user.id)
        .maybeSingle(),
    ]);

    const txns = ((txRes as { data: EarningTxn[] | null }).data || []) as EarningTxn[];
    const ledger = (ledgerRes.data || []) as Array<{ cash_collected_gnf: number; commission_owed_gnf: number; settled_amount_gnf: number; created_at: string }>;
    const profile = profileRes.data as { cash_debt_gnf: number; debt_limit_gnf: number } | null;

    // Build weekly buckets (Mon..Sun)
    const buckets: DayBucket[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart);
      d.setDate(weekStart.getDate() + i);
      buckets.push({ day: DAY_LABELS[(d.getDay() + 7) % 7], amount: 0, rides: 0, date: d.toISOString() });
    }
    let weekGnf = 0;
    let todayGnf = 0;
    let completedToday = 0;
    let missionEarningsAvailable = false;
    for (const t of txns) {
      const when = new Date(t.created_at);
      const amt = t.amount_gnf || 0;
      if (t.type === "mission_earning" && amt > 0) missionEarningsAvailable = true;
      const idx = Math.floor((when.getTime() - weekStart.getTime()) / 86_400_000);
      if (idx >= 0 && idx < 7) {
        buckets[idx].amount += amt;
        buckets[idx].rides += 1;
      }
      weekGnf += amt;
      if (when >= todayStart) {
        todayGnf += amt;
        completedToday += 1;
      }
    }

    const cashCollectedWeek = ledger.reduce((s, l) => s + (l.cash_collected_gnf || 0), 0);
    const commissionDueWeek = ledger.reduce((s, l) => s + Math.max(0, (l.commission_owed_gnf || 0) - (l.settled_amount_gnf || 0)), 0);

    setState({
      loading: false,
      todayGnf,
      weekGnf,
      weeklyBuckets: buckets,
      completedToday,
      completedWeek: txns.filter((t) => t.type === "ride_earning").length,
      cashCollectedWeek,
      commissionDueWeek,
      cashDebtGnf: profile?.cash_debt_gnf ?? 0,
      debtLimitGnf: profile?.debt_limit_gnf ?? 0,
      recent: txns.slice(0, 10),
      missionEarningsAvailable,
    });
  }, [user?.id]);

  useEffect(() => { refetch(); }, [refetch]);

  return { ...state, refetch };
}