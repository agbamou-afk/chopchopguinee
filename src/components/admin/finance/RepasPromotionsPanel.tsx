import { useCallback, useEffect, useState } from "react";
import { Loader2, Megaphone, ShieldAlert } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { fmtDateTime } from "@/lib/admin/financePolicy";

/**
 * R5.F — Repas promotion overlay.
 * A promotion NEVER overwrites the base price: it is a temporary, dated
 * discount on top of the effective policy. Courier compensation is unaffected.
 */
interface PromoRow {
  id: string;
  name: string;
  reason: string;
  fulfillment_scope: string;
  delivery_fee_override_gnf: number | null;
  delivery_discount_gnf: number | null;
  enabled: boolean;
  starts_at: string;
  ends_at: string;
}

const gnf = (v: number | null) =>
  v === null ? "—" : `${Number(v).toLocaleString("fr-FR")} GNF`;

function localInput(offsetMs: number) {
  const d = new Date(Date.now() + offsetMs);
  d.setSeconds(0, 0);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function RepasPromotionsPanel({ isGodAdmin }: { isGodAdmin: boolean }) {
  const [rows, setRows] = useState<PromoRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [name, setName] = useState("");
  const [reason, setReason] = useState("");
  const [discount, setDiscount] = useState("");
  const [startsAt, setStartsAt] = useState(localInput(60 * 60 * 1000));
  const [endsAt, setEndsAt] = useState(localInput(8 * 24 * 60 * 60 * 1000));

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await (supabase as any)
      .from("repas_pricing_promotions")
      .select("*")
      .order("starts_at", { ascending: false })
      .limit(50);
    if (error) {
      toast({ title: "Chargement impossible", description: error.message, variant: "destructive" });
    }
    setRows((data ?? []) as PromoRow[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const create = async () => {
    setSaving(true);
    const { error } = await (supabase as any).rpc("admin_set_repas_promotion", {
      p_name: name,
      p_reason: reason,
      p_starts_at: new Date(startsAt).toISOString(),
      p_ends_at: new Date(endsAt).toISOString(),
      p_fulfillment_scope: "delivery",
      p_delivery_fee_override_gnf: null,
      p_delivery_discount_gnf: Number(discount || 0),
    });
    setSaving(false);
    if (error) {
      toast({ title: "Refusé par le serveur", description: error.message, variant: "destructive" });
      return;
    }
    toast({ title: "Campagne programmée" });
    setName("");
    setReason("");
    setDiscount("");
    void load();
  };

  const disable = async (id: string) => {
    const why = window.prompt("Raison de l'arrêt de la campagne (obligatoire)");
    if (!why) return;
    const { error } = await (supabase as any).rpc("admin_disable_repas_promotion", {
      p_id: id,
      p_reason: why,
    });
    if (error) {
      toast({ title: "Refusé par le serveur", description: error.message, variant: "destructive" });
      return;
    }
    toast({ title: "Campagne arrêtée" });
    void load();
  };

  const now = Date.now();

  return (
    <div className="space-y-3">
      <Card className="p-4 space-y-1">
        <div className="flex items-center gap-2">
          <Megaphone className="w-4 h-4 text-muted-foreground" />
          <h3 className="font-bold">Campagnes Repas</h3>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Une campagne réduit temporairement le prix de livraison payé par le client. Le prix de
          base reste inchangé et la rémunération du coursier n'est jamais réduite : l'écart est
          pris en charge par CHOPCHOP. La campagne expire seule à la date de fin.
        </p>
      </Card>

      {isGodAdmin ? (
        <Card className="p-4 space-y-3">
          <div className="grid sm:grid-cols-2 gap-3">
            <div>
              <Label className="text-xs">Nom de la campagne</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Ramadan 2026" />
            </div>
            <div>
              <Label className="text-xs">Réduction livraison (GNF)</Label>
              <Input
                type="number"
                value={discount}
                onChange={(e) => setDiscount(e.target.value)}
                placeholder="5000"
              />
            </div>
            <div>
              <Label className="text-xs">Début</Label>
              <Input type="datetime-local" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} />
            </div>
            <div>
              <Label className="text-xs">Fin</Label>
              <Input type="datetime-local" value={endsAt} onChange={(e) => setEndsAt(e.target.value)} />
            </div>
          </div>
          <div>
            <Label className="text-xs">Raison (obligatoire, journalisée)</Label>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Campagne saisonnière" />
          </div>
          <Button
            className="w-full gradient-primary"
            disabled={saving || name.trim().length < 3 || reason.trim().length < 5 || !discount}
            onClick={create}
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Programmer la campagne"}
          </Button>
        </Card>
      ) : (
        <Card className="p-3 flex items-center gap-2 text-xs text-muted-foreground">
          <ShieldAlert className="w-4 h-4" />
          Lecture seule. Seul un God Admin peut créer ou arrêter une campagne.
        </Card>
      )}

      <Card className="p-4 space-y-2">
        <h4 className="text-sm font-semibold">Historique des campagnes</h4>
        {loading ? (
          <Loader2 className="w-4 h-4 animate-spin" />
        ) : rows.length === 0 ? (
          <p className="text-[11px] text-muted-foreground">Aucune campagne enregistrée.</p>
        ) : (
          rows.map((p) => {
            const active =
              p.enabled && new Date(p.starts_at).getTime() <= now && new Date(p.ends_at).getTime() > now;
            const upcoming = p.enabled && new Date(p.starts_at).getTime() > now;
            return (
              <div key={p.id} className="border-t border-border pt-2 first:border-0 first:pt-0">
                <div className="flex items-center justify-between gap-2 flex-wrap">
                  <span className="text-sm font-medium">{p.name}</span>
                  <Badge variant={active ? "secondary" : upcoming ? "outline" : "destructive"}>
                    {active ? "En cours" : upcoming ? "Programmée" : p.enabled ? "Terminée" : "Arrêtée"}
                  </Badge>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  {p.delivery_discount_gnf !== null
                    ? `Réduction ${gnf(p.delivery_discount_gnf)}`
                    : `Prix imposé ${gnf(p.delivery_fee_override_gnf)}`}{" "}
                  · {fmtDateTime(p.starts_at)} → {fmtDateTime(p.ends_at)}
                </p>
                <p className="text-[11px] text-muted-foreground">Raison : {p.reason}</p>
                {isGodAdmin && p.enabled && (
                  <Button size="sm" variant="outline" className="mt-1 h-7 text-[11px]" onClick={() => disable(p.id)}>
                    Arrêter
                  </Button>
                )}
              </div>
            );
          })
        )}
      </Card>
    </div>
  );
}
