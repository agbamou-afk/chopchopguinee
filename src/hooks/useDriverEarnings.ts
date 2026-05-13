import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface CompletedRide {
  id: string;
  mode: string;
  fare_gnf: number;
  driver_earning_gnf: number;
  completed_at: string | null;
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
  recent: CompletedRide[];
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
  });

  const refetch = useCallback(async () => {
    if (!user) return;
    setState((s) => ({ ...s, loading: true }));
    const weekStart = startOfWeek(new Date());
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);

    const [ridesRes, ledgerRes, profileRes] = await Promise.all([
      supabase
        .from("rides")
        .select("id,mode,fare_gnf,driver_earning_gnf,completed_at,created_at,status")
        .eq("driver_id", user.id)
        .eq("status", "completed")
        .gte("completed_at", weekStart.toISOString())
        .order("completed_at", { ascending: false })
        .limit(200),
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

    const rides = (ridesRes.data || []) as CompletedRide[];
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
    for (const r of rides) {
      const completed = r.completed_at ? new Date(r.completed_at) : null;
      if (!completed) continue;
      const idx = Math.floor((completed.getTime() - weekStart.getTime()) / 86_400_000);
      if (idx >= 0 && idx < 7) {
        buckets[idx].amount += r.driver_earning_gnf || 0;
        buckets[idx].rides += 1;
      }
      weekGnf += r.driver_earning_gnf || 0;
      if (completed >= todayStart) {
        todayGnf += r.driver_earning_gnf || 0;
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
      completedWeek: rides.length,
      cashCollectedWeek,
      commissionDueWeek,
      cashDebtGnf: profile?.cash_debt_gnf ?? 0,
      debtLimitGnf: profile?.debt_limit_gnf ?? 0,
      recent: rides.slice(0, 8),
    });
  }, [user?.id]);

  useEffect(() => { refetch(); }, [refetch]);

  return { ...state, refetch };
}