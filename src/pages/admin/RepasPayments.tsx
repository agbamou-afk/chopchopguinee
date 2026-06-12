import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { Navigate } from "react-router-dom";
import { ModulePage } from "@/components/admin/ModulePage";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";
import { Loader2, RefreshCw, Link2, PlayCircle } from "lucide-react";

type QueueRow = {
  food_order_id: string;
  user_id: string | null;
  restaurant_id: string;
  merchant_store_id: string | null;
  payment_method: string;
  payment_status: string;
  settlement_state: string;
  payment_intent_id: string | null;
  payment_intent_state: string | null;
  subtotal_gnf: number;
  eligible_for_capture: boolean;
  eligible_for_settlement: boolean;
  reason: string;
  created_at: string;
};

type Store = { id: string; name: string; onboarding_status: string | null };

const REASON_LABELS: Record<string, { label: string; tone: "default" | "secondary" | "destructive" | "outline" }> = {
  ready_to_capture: { label: "Prêt à capturer", tone: "default" },
  missing_merchant_store_id: { label: "Marchand non lié", tone: "destructive" },
  no_payment_intent: { label: "Aucune intention", tone: "outline" },
  already_settled: { label: "Déjà réglé", tone: "secondary" },
  auth_failed: { label: "Paiement non autorisé", tone: "destructive" },
  not_wallet_order: { label: "Pas CHOP Wallet", tone: "outline" },
  ok: { label: "OK", tone: "secondary" },
};

export default function RepasPayments() {
  const { ready, isAdmin } = useAdminAuth();
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [restoNames, setRestoNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const [linkOpen, setLinkOpen] = useState(false);
  const [linkRestaurantId, setLinkRestaurantId] = useState<string | null>(null);
  const [storeSearch, setStoreSearch] = useState("");
  const [stores, setStores] = useState<Store[]>([]);

  const loadQueue = async () => {
    setLoading(true);
    const { data, error } = await (supabase as any).rpc("admin_preview_repas_payment_settlement", { p_limit: 200 });
    if (error) {
      toast.error("Chargement impossible", { description: error.message });
      setRows([]);
    } else {
      const list = (data ?? []) as QueueRow[];
      setRows(list);
      const ids = Array.from(new Set(list.map((r) => r.restaurant_id)));
      if (ids.length) {
        const { data: r } = await (supabase as any).from("food_restaurants").select("id,name").in("id", ids);
        const map: Record<string, string> = {};
        (r ?? []).forEach((x: any) => { map[x.id] = x.name; });
        setRestoNames(map);
      }
    }
    setLoading(false);
  };

  useEffect(() => { if (isAdmin) loadQueue(); }, [isAdmin]);

  const openLink = async (restaurantId: string) => {
    setLinkRestaurantId(restaurantId);
    setStoreSearch("");
    setLinkOpen(true);
    const { data } = await (supabase as any)
      .from("merchant_stores")
      .select("id,name,onboarding_status")
      .order("name", { ascending: true })
      .limit(200);
    setStores((data ?? []) as Store[]);
  };

  const submitLink = async (storeId: string) => {
    if (!linkRestaurantId) return;
    const { data, error } = await (supabase as any).rpc("admin_link_restaurant_to_merchant_store", {
      p_restaurant_id: linkRestaurantId,
      p_merchant_store_id: storeId,
    });
    if (error) { toast.error("Liaison échouée", { description: error.message }); return; }
    toast.success("Marchand lié à ce restaurant.");
    setLinkOpen(false);
    setLinkRestaurantId(null);
    await loadQueue();
    return data;
  };

  const capture = async (row: QueueRow) => {
    if (!confirm(
      `Capturer ${formatGNF(row.subtotal_gnf)} pour ${restoNames[row.restaurant_id] ?? row.restaurant_id} ?`,
    )) return;
    setBusyId(row.food_order_id);
    // Prefer trusted completion (state -> completed + capture + settle, idempotent).
    // Falls back to manual admin capture for orders already completed but un-captured.
    const { data, error } = await (supabase as any).rpc("repas_complete_order", {
      p_food_order_id: row.food_order_id,
      p_reason: "Admin completion via Repas payments queue",
    });
    setBusyId(null);
    if (error) { toast.error("Complétion échouée", { description: error.message }); return; }
    const res = (data ?? {}) as { ok?: boolean; capture?: { ok?: boolean; captured?: boolean; settled?: boolean; reason?: string } };
    const cap = res.capture ?? {};
    if (cap.settled) toast.success("Commande terminée. Paiement capturé et règlement marchand traité.");
    else if (cap.captured) toast.message("Commande terminée. Règlement à vérifier.", { description: cap.reason });
    else toast.message("Commande terminée.", { description: cap.reason ?? "" });
    await loadQueue();
  };

  const filteredStores = useMemo(() => {
    const q = storeSearch.trim().toLowerCase();
    if (!q) return stores;
    return stores.filter((s) => s.name?.toLowerCase().includes(q));
  }, [stores, storeSearch]);

  if (!ready) return null;
  if (!isAdmin) return <Navigate to="/no-access" replace />;

  return (
    <ModulePage module="repas" title="Repas · Paiements & Règlements" subtitle="File de capture CHOPPay et liaison marchand">
      <div className="flex items-center justify-between mb-4">
        <p className="text-sm text-muted-foreground">
          {loading ? "Chargement…" : `${rows.length} commande${rows.length > 1 ? "s" : ""} CHOP Wallet`}
        </p>
        <Button variant="outline" size="sm" onClick={loadQueue} disabled={loading}>
          <RefreshCw className="w-4 h-4 mr-2" /> Rafraîchir
        </Button>
      </div>

      <div className="rounded-lg border border-border bg-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs text-muted-foreground">
              <tr>
                <th className="text-left p-3">Restaurant</th>
                <th className="text-left p-3">Montant</th>
                <th className="text-left p-3">Paiement</th>
                <th className="text-left p-3">Intention</th>
                <th className="text-left p-3">Règlement</th>
                <th className="text-left p-3">Statut</th>
                <th className="text-right p-3">Action</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !loading && (
                <tr><td colSpan={7} className="p-6 text-center text-muted-foreground">Aucune commande CHOP Wallet.</td></tr>
              )}
              {rows.map((r) => {
                const reason = REASON_LABELS[r.reason] ?? { label: r.reason, tone: "outline" as const };
                const canCapture = r.eligible_for_capture;
                const needsLink = r.reason === "missing_merchant_store_id";
                return (
                  <tr key={r.food_order_id} className="border-t border-border">
                    <td className="p-3">
                      <div className="font-medium">{restoNames[r.restaurant_id] ?? "—"}</div>
                      <div className="text-xs text-muted-foreground font-mono">{r.food_order_id.slice(0, 8)}</div>
                    </td>
                    <td className="p-3">{formatGNF(r.subtotal_gnf)}</td>
                    <td className="p-3">{r.payment_status}</td>
                    <td className="p-3">{r.payment_intent_state ?? "—"}</td>
                    <td className="p-3">{r.settlement_state}</td>
                    <td className="p-3"><Badge variant={reason.tone}>{reason.label}</Badge></td>
                    <td className="p-3 text-right space-x-2 whitespace-nowrap">
                      {needsLink && (
                        <Button size="sm" variant="outline" onClick={() => openLink(r.restaurant_id)}>
                          <Link2 className="w-4 h-4 mr-1" /> Lier marchand
                        </Button>
                      )}
                      <Button size="sm" disabled={!canCapture || busyId === r.food_order_id} onClick={() => capture(r)}>
                        {busyId === r.food_order_id ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <PlayCircle className="w-4 h-4 mr-1" />}
                        Capturer & régler
                      </Button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      <Dialog open={linkOpen} onOpenChange={setLinkOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Lier le restaurant à un marchand</DialogTitle>
            <DialogDescription>
              Choisis un marchand approuvé. Le règlement Repas créditera ce portefeuille.
            </DialogDescription>
          </DialogHeader>
          <Input
            placeholder="Rechercher un marchand…"
            value={storeSearch}
            onChange={(e) => setStoreSearch(e.target.value)}
          />
          <div className="max-h-72 overflow-y-auto border border-border rounded-md divide-y divide-border">
            {filteredStores.length === 0 && (
              <div className="p-4 text-sm text-muted-foreground text-center">Aucun marchand trouvé.</div>
            )}
            {filteredStores.map((s) => {
              const isApproved = (s.onboarding_status ?? "").toLowerCase() === "approved";
              return (
                <div key={s.id} className="flex items-center justify-between p-3">
                  <div>
                    <div className="font-medium">{s.name}</div>
                    <div className="text-xs text-muted-foreground">
                      {s.onboarding_status ?? "—"}{!isApproved && " · ⚠ non approuvé"}
                    </div>
                  </div>
                  <Button size="sm" variant={isApproved ? "default" : "outline"} onClick={() => submitLink(s.id)}>
                    Lier
                  </Button>
                </div>
              );
            })}
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setLinkOpen(false)}>Annuler</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </ModulePage>
  );
}