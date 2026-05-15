import { Bike, QrCode, Wallet, ArrowDownLeft, ArrowUpRight, RefreshCw, UtensilsCrossed, ShoppingBag, LifeBuoy, ChevronRight, BadgeCheck, Radio, ShieldCheck } from "lucide-react";
import { cn } from "@/lib/utils";
import { formatGNF } from "@/lib/format";
import type { ActivityItem, ActivityKind } from "@/lib/activity/types";
import { formatActivityTime } from "@/lib/activity/types";

const ICONS: Record<ActivityKind, typeof Bike> = {
  ride: Bike,
  merchant_payment: QrCode,
  topup: Wallet,
  transfer_in: ArrowDownLeft,
  transfer_out: ArrowUpRight,
  refund: RefreshCw,
  payout: Wallet,
  food_order: UtensilsCrossed,
  market_order: ShoppingBag,
  support: LifeBuoy,
};

const STATUS_LABEL: Record<ActivityItem["status"], string> = {
  completed: "Confirmé",
  pending: "En attente",
  failed: "Échoué",
  cancelled: "Annulé",
  in_progress: "En cours",
};

const STATUS_TONE: Record<ActivityItem["status"], string> = {
  completed: "text-muted-foreground",
  pending: "text-secondary-foreground",
  failed: "text-destructive",
  cancelled: "text-muted-foreground",
  in_progress: "text-primary",
};

function Badge({ kind }: { kind: NonNullable<ActivityItem["badge"]> }) {
  const map = {
    choppay: { Icon: ShieldCheck, label: "CHOPPay", tone: "text-primary bg-primary/10" },
    verified: { Icon: BadgeCheck, label: "Vérifié", tone: "text-primary bg-primary/10" },
    live: { Icon: Radio, label: "En direct", tone: "text-success bg-success/10" },
  } as const;
  const { Icon, label, tone } = map[kind];
  return (
    <span className={cn("inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[10px] font-medium", tone)}>
      <Icon className="w-2.5 h-2.5" />
      {label}
    </span>
  );
}

interface ActivityRowProps {
  item: ActivityItem;
  onOpen?: (item: ActivityItem) => void;
  /** Compact variant — used in Home "Dernière activité" peek. */
  compact?: boolean;
}

export function ActivityRow({ item, onOpen, compact }: ActivityRowProps) {
  const Icon = ICONS[item.kind] ?? Wallet;
  const positive = item.amount !== undefined && item.amount > 0;
  const negative = item.amount !== undefined && item.amount < 0;

  return (
    <button
      type="button"
      onClick={() => onOpen?.(item)}
      className={cn(
        "group w-full text-left flex items-center gap-3 rounded-2xl bg-card transition-colors",
        "active:bg-muted/60 hover:bg-muted/40",
        compact ? "px-3 py-2.5" : "px-3 py-3",
      )}
    >
      <div
        className={cn(
          "shrink-0 flex items-center justify-center rounded-xl",
          compact ? "w-9 h-9" : "w-10 h-10",
          "bg-primary/10 text-primary",
        )}
      >
        <Icon className={cn(compact ? "w-4 h-4" : "w-4.5 h-4.5", "w-4 h-4")} />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <p className="text-sm font-semibold text-foreground truncate">{item.title}</p>
          {item.badge && <Badge kind={item.badge} />}
        </div>
        {item.subtitle && (
          <p className="text-xs text-muted-foreground truncate">{item.subtitle}</p>
        )}
        <p className={cn("text-[11px] mt-0.5", STATUS_TONE[item.status])}>
          {STATUS_LABEL[item.status]} · {formatActivityTime(item.occurredAt)}
        </p>
      </div>
      <div className="flex items-center gap-1 shrink-0">
        {item.amount !== undefined && (
          <span
            className={cn(
              "text-sm font-semibold tabular-nums",
              positive && "text-success",
              negative && "text-foreground",
              !positive && !negative && "text-foreground",
            )}
          >
            {positive ? "+" : ""}
            {formatGNF(item.amount)}
          </span>
        )}
        {onOpen && <ChevronRight className="w-4 h-4 text-muted-foreground/60" />}
      </div>
    </button>
  );
}