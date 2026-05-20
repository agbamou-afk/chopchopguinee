import { useState } from "react";
import { Sparkles, Bike, UtensilsCrossed, ShoppingBag, Package } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { MissionOfferPopup } from "./MissionOfferPopup";
import { DemoActiveMissionCard } from "./DemoActiveMissionCard";
import { buildDemoMission } from "@/lib/missions/demoMissions";
import { type Mission, type MissionType } from "@/lib/missions/types";
import { MISSION_IDENTITY } from "@/lib/missions/pipelines";
import { toast } from "sonner";

const TYPES: { type: MissionType; icon: typeof Bike; tagline: string }[] = [
  { type: "ride", icon: Bike, tagline: "Course Moto · Kaloum → Ratoma" },
  { type: "food_delivery", icon: UtensilsCrossed, tagline: "Livraison Repas · Kipé → Ratoma" },
  { type: "marketplace_delivery", icon: ShoppingBag, tagline: "Livraison Marché · Madina → Dixinn" },
  { type: "package_delivery", icon: Package, tagline: "Colis · Matoto → Kaloum" },
];

/**
 * Demo-only launcher. Renders a single CTA ("Lancer une mission démo") that
 * opens a type picker, then surfaces a real-looking MissionRequestCard. On
 * accept, the mission is handed to DemoActiveMissionCard which advances the
 * lifecycle locally. Nothing is written to the database.
 */
export function DemoMissionLauncher() {
  const [pickerOpen, setPickerOpen] = useState(false);
  const [pending, setPending] = useState<Mission | null>(null);
  const [active, setActive] = useState<Mission | null>(null);

  const start = (type: MissionType) => {
    setPickerOpen(false);
    setPending(buildDemoMission(type));
    toast("Mission démo disponible", {
      description: MISSION_IDENTITY[type].label,
    });
  };

  const handleAccept = (_id: string) => {
    if (!pending) return;
    setActive({ ...pending, state: "heading_to_pickup", courier_id: "demo-courier" });
    setPending(null);
    toast.success("Mission acceptée (démo)");
  };

  const handleDecline = (_id: string) => {
    setPending(null);
    toast("Mission ignorée");
  };

  return (
    <div className="space-y-3">
      {!pending && !active && (
        <Button
          onClick={() => setPickerOpen(true)}
          className="w-full h-12 gradient-primary gap-2"
        >
          <Sparkles className="w-4 h-4" />
          Lancer une mission démo
        </Button>
      )}

      <MissionOfferPopup
        mission={pending}
        onAccept={handleAccept}
        onDecline={handleDecline}
        demo
      />

      {active && (
        <section className="space-y-2">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
            Mission démo en cours
          </h3>
          <DemoActiveMissionCard
            mission={active}
            onChange={setActive}
            onClose={() => setActive(null)}
          />
        </section>
      )}

      <Sheet open={pickerOpen} onOpenChange={setPickerOpen}>
        <SheetContent side="bottom" className="rounded-t-3xl">
          <SheetHeader className="text-left">
            <SheetTitle>Choisir une mission démo</SheetTitle>
            <SheetDescription>
              Mission suivie par CHOP CHOP · mode démo, aucune donnée réelle.
            </SheetDescription>
          </SheetHeader>
          <div className="mt-4 space-y-2 pb-4">
            {TYPES.map(({ type, tagline }) => {
              const id = MISSION_IDENTITY[type];
              const Icon = id.icon;
              return (
              <button
                key={type}
                type="button"
                onClick={() => start(type)}
                className={`w-full flex items-center gap-3 p-3 rounded-2xl border ${id.accent.border} hover:bg-muted/50 text-left transition-colors`}
              >
                <span className={`w-10 h-10 rounded-xl ${id.accent.iconBg} ${id.accent.iconText} flex items-center justify-center shrink-0`}>
                  <Icon className="w-5 h-5" />
                </span>
                <span className="min-w-0">
                  <span className="block text-sm font-bold text-foreground">
                    {id.label}
                  </span>
                  <span className="block text-[11px] text-muted-foreground truncate">
                    {id.subtitle} · {tagline}
                  </span>
                </span>
              </button>
              );
            })}
          </div>
        </SheetContent>
      </Sheet>
    </div>
  );
}