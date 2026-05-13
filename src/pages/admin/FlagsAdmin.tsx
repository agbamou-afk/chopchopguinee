import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { logAction } from "@/lib/admin/approvals";
import { toast } from "@/hooks/use-toast";

interface Flag { key: string; enabled: boolean; description: string | null; }

export default function FlagsAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [flags, setFlags] = useState<Flag[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { (async () => {
    const { data } = await supabase.from("feature_flags").select("*").order("key");
    setFlags((data ?? []) as Flag[]); setLoading(false);
  })(); }, []);

  const toggle = async (flag: Flag, value: boolean) => {
    setFlags(flags.map(f => f.key === flag.key ? { ...f, enabled: value } : f));
    const { error } = await supabase.from("feature_flags").update({ enabled: value }).eq("key", flag.key);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      setFlags(flags); return;
    }
    await logAction({ module: "flags", action: "flag.toggle", target_type: "feature_flag", target_id: flag.key, before: { enabled: flag.enabled }, after: { enabled: value } });
  };

  return (
    <ModulePage module="flags" title="Feature flags" subtitle="Activation/désactivation des modules de la plateforme">
      {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : (
        <div className="grid md:grid-cols-2 gap-3">
          {flags.map((f) => (
            <Card key={f.key} className="p-4 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="font-semibold">{f.key}</p>
                <p className="text-xs text-muted-foreground">{f.description ?? "—"}</p>
              </div>
              <Switch checked={f.enabled} disabled={!isSuperAdmin} onCheckedChange={(v) => toggle(f, v)} />
            </Card>
          ))}
        </div>
      )}
      {!isSuperAdmin && <p className="text-xs text-muted-foreground">Lecture seule — modifications réservées au Super Admin.</p>}
    </ModulePage>
  );
}