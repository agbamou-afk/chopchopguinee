import { useEffect, useState } from "react";
import { Check, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import {
  ALL_CAPABILITIES,
  CAPABILITY_LABEL,
  type DriverCapability,
} from "@/lib/missions/capabilities";
import { updateDriverCapabilities } from "@/lib/missions/missions";

interface CapabilityPickerProps {
  userId: string;
  capabilities: string[];
  onChange?: (next: string[]) => void;
}

/**
 * Compact chip picker for driver capabilities — keeps drivers in control of
 * what kind of missions they want to accept (rides only, deliveries, etc.).
 */
export function CapabilityPicker({ userId, capabilities, onChange }: CapabilityPickerProps) {
  const [local, setLocal] = useState<string[]>(capabilities);
  const [savingKey, setSavingKey] = useState<string | null>(null);

  useEffect(() => {
    setLocal(capabilities);
  }, [capabilities]);

  const toggle = async (cap: DriverCapability) => {
    if (savingKey) return;
    const has = local.includes(cap);
    const next = has ? local.filter((c) => c !== cap) : [...local, cap];
    if (next.length === 0) {
      toast("Gardez au moins une capacité active");
      return;
    }
    setSavingKey(cap);
    const prev = local;
    setLocal(next);
    try {
      await updateDriverCapabilities(userId, next);
      onChange?.(next);
    } catch (e) {
      setLocal(prev);
      toast.error(e instanceof Error ? e.message : "Sauvegarde impossible");
    } finally {
      setSavingKey(null);
    }
  };

  return (
    <div className="rounded-2xl bg-card border border-border/50 shadow-card p-3">
      <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground mb-2">
        Mes capacités
      </p>
      <div className="flex flex-wrap gap-1.5">
        {ALL_CAPABILITIES.map((cap) => {
          const active = local.includes(cap);
          const loading = savingKey === cap;
          return (
            <button
              key={cap}
              type="button"
              onClick={() => toggle(cap)}
              disabled={!!savingKey}
              className={cn(
                "inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold border transition-colors disabled:opacity-60",
                active
                  ? "bg-primary/10 border-primary/40 text-primary"
                  : "bg-muted/40 border-border text-muted-foreground hover:bg-muted",
              )}
            >
              {loading ? (
                <Loader2 className="w-3 h-3 animate-spin" />
              ) : active ? (
                <Check className="w-3 h-3" />
              ) : null}
              {CAPABILITY_LABEL[cap]}
            </button>
          );
        })}
      </div>
    </div>
  );
}