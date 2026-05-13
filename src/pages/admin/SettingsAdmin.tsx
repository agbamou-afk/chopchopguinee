import { useEffect, useState } from "react";
import { ModulePage } from "@/components/admin/ModulePage";
import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Loader2, Save, Smartphone } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAdminAuth } from "@/hooks/useAdminAuth";

const TOGGLES = [
  { label: "Mode sombre (admin)", desc: "Active l'interface admin en thème sombre", on: false },
  { label: "Notifications email admin", desc: "Recevoir les alertes critiques par email", on: true },
  { label: "Audit log détaillé", desc: "Enregistrer toutes les actions admin", on: true },
  { label: "Maintenance mode", desc: "Couper temporairement l'accès clients", on: false },
];

export default function SettingsAdmin() {
  const { role } = useAdminAuth();
  const canEditOM = role === "god_admin" || role === "finance_admin";
  const [omMsisdn, setOmMsisdn] = useState("");
  const [omName, setOmName] = useState("CHOP CHOP");
  const [omLoading, setOmLoading] = useState(true);
  const [omSaving, setOmSaving] = useState(false);

  useEffect(() => {
    supabase
      .from("app_settings")
      .select("value")
      .eq("key", "orange_money")
      .maybeSingle()
      .then(({ data }) => {
        const v = (data?.value ?? {}) as { merchant_msisdn?: string; merchant_name?: string };
        setOmMsisdn(v.merchant_msisdn ?? "");
        setOmName(v.merchant_name ?? "CHOP CHOP");
        setOmLoading(false);
      });
  }, []);

  const saveOM = async () => {
    setOmSaving(true);
    const { data: existing } = await supabase
      .from("app_settings")
      .select("value")
      .eq("key", "orange_money")
      .maybeSingle();
    const merged = {
      ...((existing?.value as Record<string, unknown>) ?? {}),
      merchant_msisdn: omMsisdn.trim(),
      merchant_name: omName.trim() || "CHOP CHOP",
      status: omMsisdn.trim() ? "configured" : "missing",
    };
    const { error } = await supabase
      .from("app_settings")
      .update({ value: merged, updated_at: new Date().toISOString() })
      .eq("key", "orange_money");
    setOmSaving(false);
    if (error) { toast.error(error.message); return; }
    toast.success("Compte marchand Orange Money enregistré");
  };

  return (
    <ModulePage module="settings" title="Paramètres" subtitle="Configuration plateforme et préférences admin">
      <Card className="p-5 space-y-4">
        <div className="flex items-start gap-3">
          <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
            <Smartphone className="w-5 h-5 text-primary" />
          </div>
          <div className="flex-1">
            <p className="text-sm font-semibold">Compte marchand Orange Money</p>
            <p className="text-xs text-muted-foreground">
              Numéro affiché aux clients lors d'une recharge OM. Format international recommandé (ex. +224 620 00 00 00).
            </p>
          </div>
        </div>
        {omLoading ? (
          <div className="py-6 flex justify-center"><Loader2 className="w-4 h-4 animate-spin text-muted-foreground" /></div>
        ) : (
          <div className="grid sm:grid-cols-2 gap-3">
            <div>
              <Label className="text-xs">Numéro marchand (MSISDN)</Label>
              <Input
                value={omMsisdn}
                onChange={(e) => setOmMsisdn(e.target.value)}
                placeholder="+224 620 00 00 00"
                disabled={!canEditOM}
                className="font-mono mt-1"
              />
            </div>
            <div>
              <Label className="text-xs">Nom marchand</Label>
              <Input
                value={omName}
                onChange={(e) => setOmName(e.target.value)}
                placeholder="CHOP CHOP"
                disabled={!canEditOM}
                className="mt-1"
              />
            </div>
          </div>
        )}
        <div className="flex items-center justify-between">
          <p className="text-[11px] text-muted-foreground">
            {canEditOM ? "Réservé aux admins finance / god." : "Lecture seule — droits insuffisants."}
          </p>
          <Button size="sm" onClick={saveOM} disabled={!canEditOM || omSaving || omLoading}>
            {omSaving ? <Loader2 className="w-3.5 h-3.5 animate-spin mr-1" /> : <Save className="w-3.5 h-3.5 mr-1" />}
            Enregistrer
          </Button>
        </div>
      </Card>
      <Card className="p-5 divide-y">
        {TOGGLES.map((t) => (
          <div key={t.label} className="flex items-center justify-between py-4 first:pt-0 last:pb-0">
            <div className="min-w-0">
              <Label className="text-sm font-medium">{t.label}</Label>
              <p className="text-xs text-muted-foreground">{t.desc}</p>
            </div>
            <Switch defaultChecked={t.on} />
          </div>
        ))}
      </Card>
      <Card className="p-5">
        <p className="text-sm font-semibold mb-2">Mentions légales & CGU</p>
        <p className="text-xs text-muted-foreground">CHOP GUINEE LTD — version 2026.05 · dernière mise à jour il y a 12 jours</p>
      </Card>
    </ModulePage>
  );
}
