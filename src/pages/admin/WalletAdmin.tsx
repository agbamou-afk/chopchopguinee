import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { ModulePage } from "@/components/admin/ModulePage";
import { formatGNF } from "@/lib/format";

export default function WalletAdmin() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { (async () => {
    const { data } = await supabase.from("wallet_transactions").select("*").order("created_at", { ascending: false }).limit(100);
    setRows(data ?? []); setLoading(false);
  })(); }, []);
  return (
    <ModulePage module="wallet" title="Wallet / Ledger" subtitle="Journal de toutes les transactions wallet (100 dernières)">
      <Card className="p-0 overflow-hidden">
        {loading ? (
          <div className="p-8 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50">
                <tr className="text-left">
                  <th className="p-3">Date</th><th className="p-3">Type</th><th className="p-3">Statut</th>
                  <th className="p-3 text-right">Montant</th><th className="p-3">Référence</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className="border-t">
                    <td className="p-3 text-xs">{new Date(r.created_at).toLocaleString()}</td>
                    <td className="p-3">{r.type}</td>
                    <td className="p-3"><span className="text-xs px-2 py-0.5 rounded-full bg-muted">{r.status}</span></td>
                    <td className="p-3 text-right font-medium">{formatGNF(r.amount_gnf)}</td>
                    <td className="p-3 text-xs text-muted-foreground">{r.reference}</td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-muted-foreground">Aucune transaction.</td></tr>}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </ModulePage>
  );
}