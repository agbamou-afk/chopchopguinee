import { useEffect, useState } from "react";
import { SectionCard } from "./SectionCard";
import { listMerchantMissions } from "@/lib/merchant/operations";
import { MISSION_STATE_LABEL, MISSION_TYPE_SHORT, type Mission } from "@/lib/missions/types";
import { MISSION_IDENTITY } from "@/lib/missions/pipelines";

interface Props {
  merchantUserId: string;
}

export function DeliverySection({ merchantUserId }: Props) {
  const [missions, setMissions] = useState<Mission[]>([]);
  useEffect(() => {
    listMerchantMissions(merchantUserId).then(setMissions).catch(() => { /* calm */ });
  }, [merchantUserId]);

  const active = missions.filter((m) => m.state !== "delivered" && m.state !== "failed");

  return (
    <SectionCard title="Livraison" hint="Coursiers en cours">
      {active.length === 0 && (
        <p className="text-sm text-muted-foreground">Aucune livraison en cours.</p>
      )}
      <div className="space-y-2">
        {active.map((m) => {
          const id = MISSION_IDENTITY[m.type];
          const Icon = id.icon;
          return (
            <div key={m.id} className={`rounded-xl border p-3 bg-muted/30 ${id.accent.border}`}>
              <div className="flex items-center gap-2">
                <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${id.accent.iconBg}`}>
                  <Icon className={`w-4 h-4 ${id.accent.iconText}`} />
                </div>
                <div className="flex-1 min-w-0">
                  <p className={`text-xs font-semibold ${id.accent.chipText}`}>{MISSION_TYPE_SHORT[m.type]}</p>
                  <p className="text-sm text-foreground truncate">{MISSION_STATE_LABEL[m.state]}</p>
                </div>
              </div>
              {m.payload_summary && (
                <p className="text-xs text-muted-foreground mt-1 truncate">{m.payload_summary}</p>
              )}
            </div>
          );
        })}
      </div>
    </SectionCard>
  );
}