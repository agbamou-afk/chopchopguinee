import { useEffect, useState } from "react";
import { Loader2, ShieldAlert } from "lucide-react";
import { refreshFeatureFlags } from "@/lib/flags/featureFlags";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { toast } from "@/hooks/use-toast";

interface Flag { key: string; enabled: boolean; description: string | null; }

export default function FlagsAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [flags, setFlags] = useState<Flag[]>([]);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<{ flag: Flag; value: boolean } | null>(null);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);

  const load = async () => {
    const { data } = await supabase.from("feature_flags").select("*").order("key");
    setFlags((data ?? []) as Flag[]);
    setLoading(false);
  };
  useEffect(() => { void load(); }, []);

  /**
   * Flags are mutated ONLY through `admin_set_feature_flag` (SECURITY DEFINER,
   * God-Admin only, audited). Direct table writes are revoked at the database.
   */
  const confirmToggle = async () => {
    if (!pending) return;
    setSaving(true);
    const { error } = await supabase.rpc("admin_set_feature_flag", {
      p_key: pending.flag.key, p_enabled: pending.value, p_note: reason.trim(),
    });
    setSaving(false);
    if (error) {
      toast({ title: "Refusé par le serveur", description: error.message, variant: "destructive" });
      return;
    }
    toast({ title: `${pending.flag.key} — ${pending.value ? "activé" : "désactivé"}` });
    setPending(null); setReason("");
    void load();
    // Reflect the audited verdict in THIS browser's shared flag cache
    // immediately, without waiting for the Realtime round-trip.
    void refreshFeatureFlags();
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
              <Switch
                checked={f.enabled}
                disabled={!isSuperAdmin}
                onCheckedChange={(v) => { setReason(""); setPending({ flag: f, value: v }); }}
              />
            </Card>
          ))}
        </div>
      )}
      {!isSuperAdmin && <p className="text-xs text-muted-foreground">Lecture seule — modifications réservées au Super Admin.</p>}

      <Dialog open={!!pending} onOpenChange={(v) => { if (!saving && !v) { setPending(null); setReason(""); } }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              {pending?.value ? "Activer" : "Désactiver"} « {pending?.flag.key} »
            </DialogTitle>
            <DialogDescription>
              Écriture auditée uniquement (auteur, horodatage, avant/après). Aucune modification directe
              de la table n'est possible.
            </DialogDescription>
          </DialogHeader>
          <div className="flex items-start gap-2 text-[11px] text-muted-foreground">
            <ShieldAlert className="w-3.5 h-3.5 mt-0.5 shrink-0" />
            {pending?.flag.enabled ? "Actuellement actif" : "Actuellement inactif"} →{" "}
            {pending?.value ? "actif" : "inactif"}
          </div>
          <div>
            <Label className="text-xs" htmlFor="flag-reason">Motif (obligatoire)</Label>
            <Textarea id="flag-reason" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
          <DialogFooter>
            <Button variant="outline" disabled={saving} onClick={() => { setPending(null); setReason(""); }}>
              Annuler
            </Button>
            <Button disabled={saving || reason.trim().length < 5} onClick={confirmToggle}>
              {saving ? "Enregistrement…" : "Confirmer"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </ModulePage>
  );
}