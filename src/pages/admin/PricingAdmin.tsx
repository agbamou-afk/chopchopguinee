import { useEffect, useState } from "react";
import { Bike, Car, Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "@/hooks/use-toast";
import { ModulePage, ComingSoon } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { logAction } from "@/lib/admin/approvals";

interface Fare { id: string; ride_type: string; base_price: number; price_per_km: number; currency: string; }

export default function PricingAdmin() {
  const { can } = useAdminAuth();
  const editable = can("pricing", "edit");
  const [fares, setFares] = useState<Fare[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { (async () => {
    const { data } = await supabase.from("fare_settings").select("*").order("ride_type");
    setFares((data ?? []) as Fare[]);
    setLoading(false);
  })(); }, []);

  return (
    <ModulePage module="pricing" title="Tarification" subtitle="Grille tarifaire par service">
      <Tabs defaultValue="rides">
        <TabsList>
          <TabsTrigger value="rides">Moto / TokTok</TabsTrigger>
          <TabsTrigger value="envoyer">Envoyer</TabsTrigger>
          <TabsTrigger value="repas">Repas</TabsTrigger>
          <TabsTrigger value="marche">Marché</TabsTrigger>
          <TabsTrigger value="wallet">Wallet</TabsTrigger>
        </TabsList>
        <TabsContent value="rides" className="space-y-3 mt-4">
          {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : fares.map((f) => (
            <FareRow key={f.id} fare={f} editable={editable} onSaved={(updated) => setFares(fares.map(x => x.id === updated.id ? updated : x))} />
          ))}
        </TabsContent>
        <TabsContent value="envoyer" className="mt-4"><ComingSoon description="Tarification livraisons Envoyer." /></TabsContent>
        <TabsContent value="repas" className="mt-4"><ComingSoon description="Frais de livraison Repas, commission restaurants, seuil livraison gratuite." /></TabsContent>
        <TabsContent value="marche" className="mt-4"><ComingSoon description="Annonces boostées, commission de livraison, abonnement marchand." /></TabsContent>
        <TabsContent value="wallet" className="mt-4"><ComingSoon description="Frais de top-up, commission agent, montants min/max." /></TabsContent>
      </Tabs>
    </ModulePage>
  );
}

function FareRow({ fare, editable, onSaved }: { fare: Fare; editable: boolean; onSaved: (f: Fare) => void }) {
  const [base, setBase] = useState(String(fare.base_price));
  const [perKm, setPerKm] = useState(String(fare.price_per_km));
  const [saving, setSaving] = useState(false);
  const Icon = fare.ride_type === "moto" ? Bike : Car;
  const save = async () => {
    setSaving(true);
    const before = { base_price: fare.base_price, price_per_km: fare.price_per_km };
    const after = { base_price: Number(base), price_per_km: Number(perKm) };
    const { error } = await supabase.from("fare_settings").update(after).eq("id", fare.id);
    if (error) { toast({ title: "Erreur", description: error.message }); setSaving(false); return; }
    await logAction({ module: "pricing", action: "fare.update", target_type: "fare_settings", target_id: fare.id, before, after });
    toast({ title: "Tarif mis à jour" });
    onSaved({ ...fare, ...after });
    setSaving(false);
  };
  return (
    <Card className="p-4">
      <div className="flex items-center gap-3 mb-3">
        <div className="w-9 h-9 rounded-xl gradient-primary flex items-center justify-center">
          <Icon className="w-5 h-5 text-primary-foreground" />
        </div>
        <div>
          <h3 className="font-semibold capitalize">{fare.ride_type}</h3>
          <p className="text-xs text-muted-foreground">Devise: {fare.currency}</p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div><Label className="text-xs">Prix de base</Label><Input type="number" value={base} disabled={!editable} onChange={(e) => setBase(e.target.value)} /></div>
        <div><Label className="text-xs">Prix / km</Label><Input type="number" value={perKm} disabled={!editable} onChange={(e) => setPerKm(e.target.value)} /></div>
      </div>
      <Button className="w-full mt-3 gradient-primary" disabled={!editable || saving} onClick={save}>
        {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : editable ? "Enregistrer" : "Lecture seule"}
      </Button>
    </Card>
  );
}