import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { toast } from "@/hooks/use-toast";
import {
  listIntents,
  confirmIntent,
  failIntent,
  stateLabel,
  providerLabel,
  type PaymentIntent,
} from "@/lib/payments";
import { formatGNF } from "@/lib/format";

export default function PaymentsAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [items, setItems] = useState<PaymentIntent[]>([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      setItems(await listIntents({ limit: 200 }));
    } catch (e) {
      toast({ title: "Erreur", description: (e as Error).message });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const onConfirm = async (id: string) => {
    try { await confirmIntent(id, undefined, "admin test confirmation"); await load(); }
    catch (e) { toast({ title: "Erreur", description: (e as Error).message }); }
  };
  const onFail = async (id: string) => {
    try { await failIntent(id, "admin marked failed"); await load(); }
    catch (e) { toast({ title: "Erreur", description: (e as Error).message }); }
  };

  return (
    <ModulePage module="payments" title="Paiements (intents)" subtitle="Suivi des intents et états provider WONGO">
      {loading ? (
        <Loader2 className="w-5 h-5 animate-spin" />
      ) : items.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucun intent pour l'instant.</p>
      ) : (
        <div className="space-y-2">
          {items.map((it) => (
            <Card key={it.id} className="p-3 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="font-semibold text-sm truncate">
                  {it.internal_reference} · {providerLabel(it.provider)} · {it.purpose}
                </p>
                <p className="text-xs text-muted-foreground">
                  {formatGNF(it.amount_gnf)} · {stateLabel(it.state)} · {new Date(it.created_at).toLocaleString("fr-FR")}
                </p>
              </div>
              {(it.state === "pending" || it.state === "processing") && isSuperAdmin && (
                <div className="flex gap-2 shrink-0">
                  <Button size="sm" variant="outline" onClick={() => onConfirm(it.id)}>Confirmer (test)</Button>
                  <Button size="sm" variant="ghost" onClick={() => onFail(it.id)}>Marquer échec</Button>
                </div>
              )}
            </Card>
          ))}
        </div>
      )}
      {!isSuperAdmin && (
        <p className="text-xs text-muted-foreground mt-3">
          Lecture seule — confirmation test réservée au Super Admin.
        </p>
      )}
    </ModulePage>
  );
}