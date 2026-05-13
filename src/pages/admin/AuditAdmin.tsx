import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { ModulePage } from "@/components/admin/ModulePage";

export default function AuditAdmin() {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { (async () => {
    const { data } = await supabase.from("audit_logs").select("*").order("created_at", { ascending: false }).limit(200);
    setRows(data ?? []); setLoading(false);
  })(); }, []);
  return (
    <ModulePage module="audit" title="Audit logs" subtitle="Toutes les actions admin tracées (200 dernières)">
      <Card className="p-0 overflow-hidden">
        {loading ? <div className="p-8 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50">
                <tr className="text-left">
                  <th className="p-3">Date</th><th className="p-3">Module</th><th className="p-3">Action</th>
                  <th className="p-3">Cible</th><th className="p-3">Acteur</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className="border-t">
                    <td className="p-3 text-xs">{new Date(r.created_at).toLocaleString()}</td>
                    <td className="p-3">{r.module}</td>
                    <td className="p-3 font-medium">{r.action}</td>
                    <td className="p-3 text-xs text-muted-foreground">{r.target_type ?? "—"} {r.target_id ? `· ${r.target_id.slice(0, 8)}` : ""}</td>
                    <td className="p-3 text-xs text-muted-foreground">{r.actor_role ?? "—"}</td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-muted-foreground">Aucun log.</td></tr>}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </ModulePage>
  );
}