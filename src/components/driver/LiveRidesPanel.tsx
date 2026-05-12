import { useEffect, useState, useCallback } from "react";
import { motion } from "framer-motion";
import { MapPin, Loader2, CheckCircle2, Navigation } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";

type Ride = {
  id: string;
  mode: "moto" | "toktok" | "food";
  pickup_lat: number;
  pickup_lng: number;
  dest_lat: number | null;
  dest_lng: number | null;
  fare_gnf: number;
  status: "pending" | "in_progress" | "completed" | "cancelled";
  driver_id: string | null;
  client_id: string;
  driver_earning_gnf: number;
  created_at: string;
};

const fmt = (n: number) => new Intl.NumberFormat("fr-GN").format(Math.round(n));
const MODE_LABEL: Record<Ride["mode"], string> = { moto: "Moto", toktok: "TokTok", food: "Repas" };

export function LiveRidesPanel() {
  const [uid, setUid] = useState<string | null>(null);
  const [available, setAvailable] = useState<Ride[]>([]);
  const [mine, setMine] = useState<Ride[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);

  const reload = useCallback(async (userId: string) => {
    const [{ data: pendingRows }, { data: assignedRows }] = await Promise.all([
      supabase.from("rides").select("*").eq("status", "pending").is("driver_id", null).order("created_at", { ascending: false }).limit(20),
      supabase.from("rides").select("*").eq("driver_id", userId).order("created_at", { ascending: false }).limit(20),
    ]);
    setAvailable((pendingRows ?? []) as Ride[]);
    setMine((assignedRows ?? []) as Ride[]);
  }, []);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) return;
      setUid(data.user.id);
      reload(data.user.id);
    });
  }, [reload]);

  useEffect(() => {
    if (!uid) return;
    const channel = supabase
      .channel("driver-rides")
      .on("postgres_changes", { event: "*", schema: "public", table: "rides" }, () => reload(uid))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [uid, reload]);

  const accept = async (id: string) => {
    setBusyId(id);
    const { error } = await supabase.rpc("ride_accept", { p_ride_id: id });
    setBusyId(null);
    if (error) return toast.error(error.message);
    toast.success("Course acceptée");
  };

  const complete = async (id: string, fare: number) => {
    setBusyId(id);
    const { error } = await supabase.rpc("ride_complete", {
      p_ride_id: id,
      p_actual_fare_gnf: Math.round(fare),
      p_commission_bps: 1500,
    });
    setBusyId(null);
    if (error) return toast.error(error.message);
    toast.success("Paiement reçu sur votre wallet");
  };

  return (
    <div className="space-y-4">
      <section>
        <h3 className="text-sm font-semibold text-muted-foreground mb-2 px-1">Mes courses en cours</h3>
        {mine.filter(r => r.status === "in_progress").length === 0 ? (
          <p className="text-xs text-muted-foreground px-1">Aucune course active</p>
        ) : (
          <div className="space-y-2">
            {mine.filter(r => r.status === "in_progress").map((r) => (
              <motion.div key={r.id} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
                className="rounded-2xl bg-card border border-border p-4 shadow-card">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold uppercase tracking-wide text-primary">{MODE_LABEL[r.mode]}</span>
                  <span className="font-bold">{fmt(r.fare_gnf)} GNF</span>
                </div>
                <div className="flex items-start gap-2 text-sm text-muted-foreground mb-3">
                  <MapPin className="w-4 h-4 mt-0.5 text-primary shrink-0" />
                  <span>{r.pickup_lat.toFixed(4)}, {r.pickup_lng.toFixed(4)}{r.dest_lat ? ` → ${r.dest_lat.toFixed(4)}, ${r.dest_lng?.toFixed(4)}` : ""}</span>
                </div>
                <Button className="w-full h-10" onClick={() => complete(r.id, r.fare_gnf)} disabled={busyId === r.id}>
                  {busyId === r.id ? <Loader2 className="w-4 h-4 animate-spin" /> : <><CheckCircle2 className="w-4 h-4 mr-2" /> Marquer terminée</>}
                </Button>
              </motion.div>
            ))}
          </div>
        )}
      </section>

      <section>
        <h3 className="text-sm font-semibold text-muted-foreground mb-2 px-1">Demandes disponibles</h3>
        {available.length === 0 ? (
          <p className="text-xs text-muted-foreground px-1">Aucune demande pour l'instant</p>
        ) : (
          <div className="space-y-2">
            {available.map((r) => (
              <motion.div key={r.id} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
                className="rounded-2xl bg-card border border-border p-4 shadow-card">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold uppercase tracking-wide text-primary">{MODE_LABEL[r.mode]}</span>
                  <span className="font-bold">{fmt(r.fare_gnf)} GNF</span>
                </div>
                <div className="flex items-start gap-2 text-sm text-muted-foreground mb-3">
                  <Navigation className="w-4 h-4 mt-0.5 text-primary shrink-0" />
                  <span>{r.pickup_lat.toFixed(4)}, {r.pickup_lng.toFixed(4)}{r.dest_lat ? ` → ${r.dest_lat.toFixed(4)}, ${r.dest_lng?.toFixed(4)}` : ""}</span>
                </div>
                <Button className="w-full h-10" onClick={() => accept(r.id)} disabled={busyId === r.id}>
                  {busyId === r.id ? <Loader2 className="w-4 h-4 animate-spin" /> : "Accepter"}
                </Button>
              </motion.div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}