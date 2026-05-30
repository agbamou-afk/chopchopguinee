import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { MapPin, Globe, Building2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

type Hub = {
  id: string;
  name: string;
  district: string;
  partner_type: string;
  status: string;
  address: string | null;
};

export default function ZonesAdmin() {
  const [hubs, setHubs] = useState<Hub[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from("district_hubs")
        .select("id,name,district,partner_type,status,address")
        .order("district", { ascending: true })
        .limit(500);
      setHubs((data ?? []) as Hub[]);
      setLoading(false);
    })();
  }, []);

  const stats = useMemo(() => {
    const districts = new Set(hubs.map((h) => h.district));
    return {
      country: 1,
      districts: districts.size,
      hubs: hubs.length,
      active: hubs.filter((h) => h.status === "active").length,
    };
  }, [hubs]);

  return (
    <ModulePage module="zones" title="Zones" subtitle="Districts et hubs partenaires enregistrés">
      <StatGrid items={[
        { label: "Pays", value: "1", icon: Globe },
        { label: "Districts", value: loading ? "…" : String(stats.districts), icon: Building2 },
        { label: "Hubs", value: loading ? "…" : String(stats.hubs), icon: MapPin },
        { label: "Actifs", value: loading ? "…" : String(stats.active), icon: MapPin },
      ]} />
      <div className="space-y-2">
        {loading ? (
          <Card className="p-6 text-center text-sm text-muted-foreground">Chargement…</Card>
        ) : hubs.length === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">
            Aucun hub partenaire enregistré.
          </Card>
        ) : hubs.map((h) => (
          <Card key={h.id} className="p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center">
              <MapPin className="w-5 h-5 text-primary-foreground" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-sm truncate">{h.name}</p>
              <p className="text-xs text-muted-foreground truncate">{h.district} · {h.partner_type}{h.address ? ` · ${h.address}` : ""}</p>
            </div>
            <StatusBadge status={h.status} />
          </Card>
        ))}
      </div>
    </ModulePage>
  );
}
