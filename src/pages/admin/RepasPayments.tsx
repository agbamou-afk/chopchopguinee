import { useEffect, useMemo, useState, type ReactNode } from "react";
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
import { Loader2, RefreshCw, Link2, PlayCircle, Info, AlertTriangle, CheckCircle2 } from "lucide-react";

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
type FilterKey = "all" | "ready" | "missing_link" | "settled" | "failed" | "review";

const REASON_LABELS: Record<string, { label: string; tone: "default" | "secondary" | "destructive" | "outline" }> = {
  ready_to_capture: { label: "Prêt à capturer", tone: "default" },
  missing_merchant_store_id: { label: "Marchand non lié", tone: "destructive" },
  no_payment_intent: { label: "Aucune intention", tone: "outline" },
  already_settled: { label: "Déjà réglé", tone: "secondary" },
  auth_failed: { label: "Paiement non autorisé", tone: "destructive" },
  not_wallet_order: { label: "Pas CHOP Wallet", tone: "outline" },
  ok: { label: "OK", tone: "secondary" },
};

const FILTERS: { key: FilterKey; label: string }[] = [
  { key: "all", label: "Tous" },
  { key: "ready", label: "Prêt à capturer" },
  { key: "missing_link", label: "Marchand non lié" },
  { key: "settled", label: "Déjà réglé" },
  { key: "failed", label: "Paiement échoué" },
  { key: "review", label: "À revoir" },
];

export default function RepasPayments() {
  const { ready, isAdmin } = useAdminAuth();
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [restoNames, setRestoNames] = useState<Record<string, string>>({});
  const [storeIndex, setStoreIndex] = useState<Record<string, Store>>({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterKey>("all");
  const [detailRow, setDetailRow] = useState<QueueRow | null>(null);

  const [linkOpen, setLinkOpen] = useState(false);
  const [linkRestaurantId, setLinkRestaurantId] = useState<string | null>(null);
  const [storeSearch, setStoreSearch] = useState("");
  const [stores, setStores] = useState<Store[]>([]);

  const loadQueue = async () => {
    setLoading(true);
    setLoadError(null);
    const { data, error } = await (supabase as any).rpc("admin_preview_repas_payment_settlement", { p_limit: 200 });
    if (error) {
      setLoadError(error.message ?? "Erreur inconnue");
      toast.error("Impossible de charger les paiements Repas.", { description: error.message });
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
      const storeIds = Array.from(new Set(list.map((r) => r.merchant_store_id).filter(Boolean) as string[]));
      if (storeIds.length) {
        const { data: s } = await (supabase as any)
          .from("merchant_stores")
          .select("id,name,onboarding_status")
          .in("id", storeIds);
        const map: Record<string, Store> = {};
        (s ?? []).forEach((x: any) => { map[x.id] = x as Store; });
        setStoreIndex(map);
      } else {
        setStoreIndex({});
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

  const filteredRows = useMemo(() => {
    switch (filter) {
      case "ready": return rows.filter((r) => r.eligible_for_capture);
      case "missing_link": return rows.filter((r) => r.reason === "missing_merchant_store_id");
      case "settled": return rows.filter((r) => r.settlement_state === "settled" || r.reason === "already_settled");
      case "failed": return rows.filter((r) => r.reason === "auth_failed" || r.payment_status === "failed");
      case "review": return rows.filter((r) => r.settlement_state === "needs_review");
      default: return rows;
    }
  }, [rows, filter]);

  if (!ready) return null;
  if (!isAdmin) return <Navigate to="/no-access" replace />;

  return (
    <ModulePage module="repas" title="Repas · Paiements & Règlements" subtitle="File de capture CHOPPay et liaison marchand">
      <div className="flex items-center justify-between mb-4">
        <p className="text-sm text-muted-foreground">
          {loading ? "Chargement…" : `${filteredRows.length} / ${rows.length} commande${rows.length > 1 ? "s" : ""} CHOP Wallet`}
        </p>
        <Button variant="outline" size="sm" onClick={loadQueue} disabled={loading}>
          <RefreshCw className={`w-4 h-4 mr-2 ${loading ? "animate-spin" : ""}`} /> Rafraîchir
        </Button>
      </div>

      <div className="flex gap-2 flex-wrap mb-3">
        {FILTERS.map((f) => (
          <Button
            key={f.key}
            size="sm"
            variant={filter === f.key ? "default" : "outline"}
            onClick={() => setFilter(f.key)}
          >
            {f.label}
          </Button>
        ))}
      </div>

      <div className="rounded-lg border border-border bg-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs text-muted-foreground">
              <tr>
                <th className="text-left p-3">Restaurant</th>
                <th className="text-left p-3">Marchand lié</th>
                <th className="text-left p-3">Montant</th>
                <th className="text-left p-3">Paiement</th>
                <th className="text-left p-3">Intention</th>
                <th className="text-left p-3">Règlement</th>
                <th className="text-left p-3">Statut</th>
                <th className="text-right p-3">Action</th>
              </tr>
            </thead>
            <tbody>
              {!loading && loadError && (
                <tr><td colSpan={8} className="p-6 text-center text-destructive">Impossible de charger les paiements Repas.</td></tr>
              )}
              {!loading && !loadError && filteredRows.length === 0 && (
                <tr><td colSpan={8} className="p-6 text-center text-muted-foreground">Aucun paiement Repas à traiter.</td></tr>
              )}
              {filteredRows.map((r) => {
                const reason = REASON_LABELS[r.reason] ?? { label: r.reason, tone: "outline" as const };
                const canCapture = r.eligible_for_capture;
                const needsLink = r.reason === "missing_merchant_store_id";
                const store = r.merchant_store_id ? storeIndex[r.merchant_store_id] : null;
                const storeApproved = (store?.onboarding_status ?? "").toLowerCase() === "approved";
                return (
                  <tr
                    key={r.food_order_id}
                    className="border-t border-border hover:bg-muted/30 cursor-pointer"
                    onClick={() => setDetailRow(r)}
                  >
                    <td className="p-3" onClick={(e) => e.stopPropagation()}>
                      <div className="font-medium">{restoNames[r.restaurant_id] ?? "—"}</div>
                      <div className="text-xs text-muted-foreground font-mono">{r.food_order_id.slice(0, 8)}</div>
                    </td>
                    <td className="p-3">
                      {!r.merchant_store_id ? (
                        <Badge variant="destructive">Non lié</Badge>
                      ) : store ? (
                        <div>
                          <div className="font-medium text-xs">{store.name}</div>
                          <div className="text-[11px] text-muted-foreground">
                            {storeApproved
                              ? <span className="text-emerald-600">Approuvé</span>
                              : <span className="text-amber-600">⚠ {store.onboarding_status ?? "non approuvé"}</span>}
                          </div>
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground font-mono">{r.merchant_store_id.slice(0, 8)}</span>
                      )}
                    </td>
                    <td className="p-3">{formatGNF(r.subtotal_gnf)}</td>
                    <td className="p-3">{r.payment_status}</td>
                    <td className="p-3">{r.payment_intent_state ?? "—"}</td>
                    <td className="p-3">{r.settlement_state}</td>
                    <td className="p-3"><Badge variant={reason.tone}>{reason.label}</Badge></td>
                    <td className="p-3 text-right space-x-2 whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
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

      {/* Detail drawer */}
      <Dialog open={!!detailRow} onOpenChange={(o) => !o && setDetailRow(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Détail commande</DialogTitle>
            <DialogDescription>Inspection paiement / règlement Repas</DialogDescription>
          </DialogHeader>
          {detailRow && (() => {
            const r = detailRow;
            const store = r.merchant_store_id ? storeIndex[r.merchant_store_id] : null;
            const reason = REASON_LABELS[r.reason] ?? { label: r.reason, tone: "outline" as const };
            const Row = ({ k, v }: { k: string; v: ReactNode }) => (
              <div className="flex items-start justify-between gap-3 py-1.5 border-b border-border/50 last:border-b-0">
                <span className="text-xs text-muted-foreground">{k}</span>
                <span className="text-xs font-mono text-right break-all">{v ?? "—"}</span>
              </div>
            );
            return (
              <div className="text-sm space-y-2">
                <div className="flex items-center gap-2">
                  <Badge variant={reason.tone}>{reason.label}</Badge>
                  {r.eligible_for_capture && <Badge variant="default"><CheckCircle2 className="w-3 h-3 mr-1" />Capturable</Badge>}
                  {r.settlement_state === "needs_review" && <Badge variant="destructive"><AlertTriangle className="w-3 h-3 mr-1" />À revoir</Badge>}
                </div>
                <div className="rounded-md border border-border p-3 mt-2">
                  <Row k="Commande" v={r.food_order_id} />
                  <Row k="Restaurant" v={restoNames[r.restaurant_id] ?? r.restaurant_id} />
                  <Row k="Client" v={r.user_id ?? "—"} />
                  <Row k="Sous-total" v={formatGNF(r.subtotal_gnf)} />
                  <Row k="Méthode" v={r.payment_method} />
                  <Row k="Statut paiement" v={r.payment_status} />
                  <Row k="État commande" v={r.payment_intent_state ?? "—"} />
                  <Row k="Intention paiement" v={r.payment_intent_id ?? "—"} />
                  <Row k="Règlement" v={r.settlement_state} />
                  <Row k="Créée" v={new Date(r.created_at).toLocaleString("fr-FR")} />
                </div>
                <div className="rounded-md border border-border p-3">
                  <div className="text-xs font-semibold mb-1">Marchand lié</div>
                  {!r.merchant_store_id ? (
                    <div className="text-xs text-muted-foreground">
                      Aucun marchand lié. Liez ce restaurant à un compte marchand avant règlement automatique.
                    </div>
                  ) : store ? (
                    <div className="text-xs">
                      <div className="font-medium">{store.name}</div>
                      <div className="text-muted-foreground">{store.onboarding_status ?? "—"}</div>
                      <div className="font-mono mt-1">{store.id}</div>
                    </div>
                  ) : (
                    <div className="text-xs font-mono">{r.merchant_store_id}</div>
                  )}
                </div>
                <div className="flex gap-2 pt-2 flex-wrap">
                  {!r.merchant_store_id && (
                    <Button size="sm" variant="outline" onClick={() => { setDetailRow(null); openLink(r.restaurant_id); }}>
                      <Link2 className="w-4 h-4 mr-1" /> Lier marchand
                    </Button>
                  )}
                  {r.eligible_for_capture && (
                    <Button size="sm" onClick={() => { setDetailRow(null); capture(r); }}>
                      <PlayCircle className="w-4 h-4 mr-1" /> Capturer & régler
                    </Button>
                  )}
                  <Button size="sm" variant="ghost" onClick={loadQueue}>
                    <RefreshCw className="w-4 h-4 mr-1" /> Rafraîchir
                  </Button>
                </div>
                <div className="text-[11px] text-muted-foreground flex items-start gap-1 pt-2">
                  <Info className="w-3 h-3 mt-0.5 shrink-0" />
                  <span>Capture et règlement passent par la RPC SECURITY DEFINER (admin/service_role uniquement).</span>
                </div>
              </div>
            );
          })()}
        </DialogContent>
      </Dialog>

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