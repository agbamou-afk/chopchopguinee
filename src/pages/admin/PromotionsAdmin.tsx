import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, DataTable, StatusBadge } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Megaphone, TrendingUp, Tag, Calendar } from "lucide-react";
import { useState } from "react";

const PROMOS = [
  { code: "BIENVENUE10", discount: "10%", service: "Tous", uses: "1 240 / 5 000", expires: "31/12/2026", status: "active" },
  { code: "MOTO5K", discount: "5 000 GNF", service: "Moto", uses: "412 / 1 000", expires: "30/06/2026", status: "active" },
  { code: "REPAS20", discount: "20%", service: "Repas", uses: "89 / 500", expires: "01/06/2026", status: "active" },
  { code: "RAMADAN", discount: "15%", service: "Tous", uses: "2 100 / 2 100", expires: "30/04/2026", status: "completed" },
];

export default function PromotionsAdmin() {
  const [show, setShow] = useState(false);
  return (
    <ModulePage module="promotions" title="Promotions" subtitle="Codes promo, campagnes et bonus parrainage"
      actions={<Button size="sm" className="gradient-primary" onClick={() => setShow(!show)}><Megaphone className="w-4 h-4 mr-1" /> Nouveau</Button>}>
      <StatGrid items={[
        { label: "Codes actifs", value: "12", icon: Tag, tone: "text-primary" },
        { label: "Utilisations 30j", value: "4 821", icon: TrendingUp, tone: "text-emerald-600" },
        { label: "Économies clients", value: "18.4 M GNF", icon: Tag, tone: "text-amber-600" },
        { label: "Expirent ≤ 7j", value: "3", icon: Calendar, tone: "text-rose-600" },
      ]} />
      {show && (
        <Card className="p-5 space-y-3 animate-fade-in">
          <p className="text-sm font-semibold">Nouveau code promo</p>
          <div className="grid md:grid-cols-2 gap-3">
            <div><Label className="text-xs">Code</Label><Input placeholder="EX: NOEL2026" /></div>
            <div><Label className="text-xs">Remise (% ou GNF)</Label><Input placeholder="10%" /></div>
            <div><Label className="text-xs">Service</Label><Input placeholder="Tous, Moto, Repas..." /></div>
            <div><Label className="text-xs">Date expiration</Label><Input type="date" /></div>
          </div>
          <Button className="gradient-primary">Créer</Button>
        </Card>
      )}
      <DataTable columns={["Code", "Remise", "Service", "Utilisations", "Expire", "Statut"]}
        rows={PROMOS.map((p) => [<span className="font-mono font-semibold">{p.code}</span>, p.discount, p.service, p.uses, p.expires, <StatusBadge status={p.status} />])} />
    </ModulePage>
  );
}
